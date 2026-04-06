import 'package:flutter/material.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'dart:math';

class JitsiService {
  static final JitsiService _instance = JitsiService._internal();
  factory JitsiService() => _instance;
  JitsiService._internal();

  final _jitsiMeet = JitsiMeet();

  /// Gera um nome de sala aleatório e seguro.
  String generateRoomName() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(12, (index) => chars[random.nextInt(chars.length)]).join();
  }

  /// Entra na sala Jitsi em modo de VOZ APENAS (câmera desabilitada).
  /// Para habilitar vídeo no futuro: defina startWithVideoMuted = false
  /// e camera.enabled = true nos parâmetros abaixo.
  Future<void> joinMeeting({
    required String roomName,
    required String userDisplayName,
    required String userEmail,
    String? userAvatarUrl,
  }) async {
    try {
      debugPrint('JitsiService: Entrando na sala $roomName');

      var options = JitsiMeetConferenceOptions(
        serverURL: "https://meet.ffmuc.net",
        room: roomName,
        configOverrides: {
          "prejoinPageEnabled": false,   // <- pula a tela de "Join meeting"
          "lobbyModeEnabled": false,     // <- desativa a sala de espera (Lobby)
          "startWithAudioMuted": false,
          "startWithVideoMuted": true,   // <- voz apenas; mude para false para vídeo
          "subject": "Chamada de Voz UFF",
        },
        featureFlags: {
          "prejoinpage.enabled": false,
          "lobby-mode.enabled": false,
          "is-moderator.enabled": true,        // <- Garante que o primeiro a entrar possa iniciar
          "camera.enabled": false,             // <- remove o botão de câmera da UI
          "unsecure-recording.enabled": false,
          "ios.recording.enabled": false,
          "toolbox.enabled": true,
          "invite.enabled": false,
        },
        userInfo: JitsiMeetUserInfo(
          displayName: userDisplayName,
          email: userEmail,
          avatar: userAvatarUrl,
        ),
      );

      await _jitsiMeet.join(options);
    } catch (e) {
      debugPrint('JitsiService Error: $e');
      rethrow;
    }
  }
}
