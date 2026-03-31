import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  FirebaseFirestore get _firestore => 
      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'monitora-uff');

  StreamSubscription? _callSubscription;

  Future<void> initialize() async {
    // Escuta eventos do CallKit (Aceitar/Recusar)
    FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent);
  }

  void _onCallKitEvent(CallEvent? event) async {
    if (event == null) return;

    switch (event.event) {
      case Event.actionCallAccept:
        final meetingUrl = event.body['extra']['meeting_url'];
        if (meetingUrl != null) {
          final url = Uri.parse(meetingUrl);
          if (await canLaunchUrl(url)) {
            await launchUrl(url);
          }
        }
        break;
      case Event.actionCallDecline:
        log('Chamada recusada');
        break;
      default:
        break;
    }
  }

  /// Registra o usuário e começa a ouvir chamadas para ele
  Future<void> registerUser(String email) async {
    
    // 1. Salva o token FCM (opcional para o demo com listener, mas bom ter)
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _firestore.collection('fcm_tokens').doc(email).set({
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 2. Começa a ouvir a coleção de 'calls' filtrando pelo destinatário
    _callSubscription?.cancel();
    _callSubscription = _firestore
        .collection('calls')
        .where('to', isEqualTo: email)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(_handleIncomingCalls);
    
    log('Ouvindo chamadas para: $email no banco monitora-uff');
  }

  void _handleIncomingCalls(QuerySnapshot snapshot) async {
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final callId = doc.id;
      final from = data['from'];
      final meetingUrl = data['meeting_url'];
      final timestamp = (data['timestamp'] as Timestamp).toDate();

      // Ignora chamadas antigas (mais de 1 minuto)
      if (DateTime.now().difference(timestamp).inMinutes > 1) continue;

      // Mostra a interface de chamada
      final uuid = const Uuid().v4();
      final params = CallKitParams(
        id: uuid,
        nameCaller: from,
        appName: 'Meet Demo',
        type: 0, // Video
        extra: <String, dynamic>{'meeting_url': meetingUrl, 'call_doc_id': callId},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#095D12',
          actionColor: '#4CAF50',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
      
      // Marca como 'notified' para não repetir
      await _firestore.collection('calls').doc(callId).update({'status': 'notified'});
    }
  }

  /// Dispara a sinalização para outro usuário
  Future<void> startCall(String from, String to, String meetingUrl) async {
    await _firestore.collection('calls').add({
      'from': from,
      'to': to,
      'meeting_url': meetingUrl,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    log('Sinalização de chamada enviada para $to');
  }

  void dispose() {
    _callSubscription?.cancel();
  }
}
