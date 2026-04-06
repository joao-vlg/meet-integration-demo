import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'google_meet_service.dart';
import 'jitsi_service.dart';

/// Estados possíveis de uma chamada sainte (do ponto de vista do remetente).
enum CallState { idle, calling, connected, declined, cancelled, timeout }

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  FirebaseFirestore get _firestore =>
      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'monitora-uff');

  // --- Estado da chamada sainte ---
  StreamController<CallState>? _callStateController;
  StreamSubscription<DocumentSnapshot>? _callStatusSubscription;
  Timer? _callTimeoutTimer;
  String? _currentCallDocId;
  String? _currentRoomName;

  // --- Listener de chamadas entrantes ---
  StreamSubscription? _incomingCallSubscription;

  /// Stream que o remetente ouve para saber quando a chamada foi atendida/recusada.
  Stream<CallState>? get callStateStream => _callStateController?.stream;

  /// Nome da sala da chamada sainte atual (usado para entrar no Jitsi ao aceitar).
  String? get currentRoomName => _currentRoomName;

  // ---------------------------------------------------------------------------
  // Inicialização
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent);
  }

  // ---------------------------------------------------------------------------
  // Eventos do CallKit (destinatário)
  // ---------------------------------------------------------------------------

  void _onCallKitEvent(CallEvent? event) async {
    if (event == null) return;

    final extra = event.body['extra'] as Map<dynamic, dynamic>? ?? {};
    final provider = extra['provider'] as String?;
    final meetingUrl = extra['meeting_url'] as String?;
    final roomName = extra['room_name'] as String?;
    final callDocId = extra['call_doc_id'] as String?;

    switch (event.event) {
      case Event.actionCallAccept:
        // 1. Notifica o remetente via Firestore
        if (callDocId != null) {
          try {
            await _firestore
                .collection('calls')
                .doc(callDocId)
                .update({'status': 'accepted'});
          } catch (e) {
            debugPrint('Erro ao atualizar status para accepted: $e');
          }
        }
        // 2. Destinatário entra na chamada
        if (provider == 'meet' && meetingUrl != null) {
          await GoogleMeetService().launchMeeting(meetingUrl);
        } else if (provider == 'jitsi' && roomName != null) {
          await JitsiService().joinMeeting(
            roomName: roomName,
            userDisplayName: 'Usuário UFF',
            userEmail: 'participante@id.uff.br',
          );
        }
        break;

      case Event.actionCallDecline:
        if (callDocId != null) {
          try {
            await _firestore
                .collection('calls')
                .doc(callDocId)
                .update({'status': 'declined'});
          } catch (e) {
            debugPrint('Erro ao atualizar status para declined: $e');
          }
        }
        log('Chamada recusada pelo destinatário');
        break;

      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Registro e escuta de chamadas entrantes
  // ---------------------------------------------------------------------------

  Future<void> registerUser(String email) async {
    // Salva token FCM
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _firestore.collection('fcm_tokens').doc(email).set({
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Escuta chamadas pendentes para este usuário
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = _firestore
        .collection('calls')
        .where('recipient', isEqualTo: email)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(_handleIncomingCalls);

    log('Ouvindo chamadas para: $email no banco monitora-uff');
  }

  void _handleIncomingCalls(QuerySnapshot snapshot) async {
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final callId = doc.id;
      final caller = data['caller'] as String? ?? 'Desconhecido';
      final provider = data['provider'] as String? ?? 'meet';
      final meetingUrl = data['meeting_url'] as String?;
      final roomName = data['room_name'] as String?;

      final timestampRaw = data['timestamp'] as Timestamp?;
      final timestamp = timestampRaw?.toDate() ?? DateTime.now();

      // Ignora chamadas antigas (mais de 1 minuto)
      if (DateTime.now().difference(timestamp).inMinutes > 1) continue;

      final uuid = const Uuid().v4();
      final params = CallKitParams(
        id: uuid,
        nameCaller: caller,
        appName: 'PoC UFF Calling',
        type: 0, // 0 = voz; manter 0 pois desabilitamos vídeo no Jitsi
        extra: <String, dynamic>{
          'meeting_url': meetingUrl,
          'room_name': roomName,
          'provider': provider,
          'caller': caller,
          'call_doc_id': callId,
        },
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#095D12',
          actionColor: '#4CAF50',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);

      // Marca como 'notified' para não repetir o toque
      await _firestore.collection('calls').doc(callId).update({'status': 'notified'});
    }
  }

  // ---------------------------------------------------------------------------
  // Chamada sainte — fluxo do remetente
  // ---------------------------------------------------------------------------

  /// Cria a chamada no Firestore e começa a ouvir a resposta do destinatário.
  /// Use [callStateStream] para reagir ao resultado (accepted / declined / timeout).
  Future<void> startCall(
    String caller,
    String recipient,
    String roomName,
    String provider,
  ) async {
    // Descarta qualquer chamada sainte anterior
    _cleanupOutgoingCall();

    try {
      final docRef = await _firestore.collection('calls').add({
        'caller': caller,
        'recipient': recipient,
        'meeting_url': roomName,
        'room_name': roomName,
        'provider': provider,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      _currentCallDocId = docRef.id;
      _currentRoomName = roomName;

      // Cria o broadcast stream de estado
      _callStateController = StreamController<CallState>.broadcast();
      _callStateController!.add(CallState.calling);

      // Ouve mudanças no documento da chamada
      _callStatusSubscription = docRef.snapshots().listen((snap) {
        if (!snap.exists) return;
        final status = snap.data()?['status'] as String?;
        switch (status) {
          case 'accepted':
            _callStateController?.add(CallState.connected);
            _cleanupOutgoingTimers();
            break;
          case 'declined':
            _callStateController?.add(CallState.declined);
            _cleanupOutgoingTimers();
            break;
          case 'cancelled':
            _callStateController?.add(CallState.cancelled);
            _cleanupOutgoingTimers();
            break;
        }
      });

      // Timer de timeout: 45 segundos
      _callTimeoutTimer = Timer(const Duration(seconds: 45), () async {
        _callStateController?.add(CallState.timeout);
        if (_currentCallDocId != null) {
          try {
            await _firestore
                .collection('calls')
                .doc(_currentCallDocId!)
                .update({'status': 'timeout'});
          } catch (_) {}
        }
        _cleanupOutgoingTimers();
      });

      debugPrint('Chamada criada: ${docRef.id} | $caller → $recipient via $provider');
    } catch (e) {
      _cleanupOutgoingCall();
      debugPrint('Erro ao iniciar chamada: $e');
      rethrow;
    }
  }

  /// Cancela a chamada sainte atual (acionado pelo remetente).
  Future<void> cancelCall() async {
    if (_currentCallDocId != null) {
      try {
        await _firestore
            .collection('calls')
            .doc(_currentCallDocId!)
            .update({'status': 'cancelled'});
      } catch (e) {
        debugPrint('Erro ao cancelar chamada: $e');
      }
    }
    _callStateController?.add(CallState.cancelled);
    _cleanupOutgoingTimers();
  }

  // ---------------------------------------------------------------------------
  // Helpers de limpeza
  // ---------------------------------------------------------------------------

  /// Cancela timers e listeners do Firestore da chamada sainte,
  /// mas mantém o StreamController para que o último evento seja entregue.
  void _cleanupOutgoingTimers() {
    _callStatusSubscription?.cancel();
    _callStatusSubscription = null;
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    _currentCallDocId = null;
    _currentRoomName = null;
  }

  /// Descarta completamente o estado de chamada sainte (incluindo o StreamController).
  void _cleanupOutgoingCall() {
    _cleanupOutgoingTimers();
    _callStateController?.close();
    _callStateController = null;
  }

  /// Libera todos os recursos (chamado no logout).
  void dispose() {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = null;
    _cleanupOutgoingCall();
  }
}
