import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GoogleMeetService {
  static final GoogleMeetService _instance = GoogleMeetService._internal();
  factory GoogleMeetService() => _instance;
  GoogleMeetService._internal();

  /// Cria uma reunião no Google Calendar e retorna o link do Meet
  Future<String?> createMeeting(GoogleSignInAccount user, String recipientEmail) async {
    try {
      final scopes = [calendar.CalendarApi.calendarEventsScope];
      final authorization = await user.authorizationClient.authorizeScopes(scopes);
      
      final accessToken = authorization.accessToken;

      // Cria um cliente autenticado para a API do Google
      final authenticateClient = auth.authenticatedClient(
        http.Client(),
        auth.AccessCredentials(
          auth.AccessToken(
            'Bearer',
            accessToken,
            DateTime.now().add(const Duration(hours: 1)).toUtc(),
          ),
          null,
          scopes,
        ),
      );

      final calendarApi = calendar.CalendarApi(authenticateClient);

      // Define o evento com dados de conferência (Google Meet)
      final event = calendar.Event(
        summary: 'Chamada do Google Meet (PoC)',
        description: 'Chamada instantânea iniciada via App UFF',
        start: calendar.EventDateTime(dateTime: DateTime.now()),
        end: calendar.EventDateTime(dateTime: DateTime.now().add(const Duration(hours: 1))),
        attendees: [calendar.EventAttendee(email: recipientEmail)],
        conferenceData: calendar.ConferenceData(
          createRequest: calendar.CreateConferenceRequest(
            requestId: DateTime.now().millisecondsSinceEpoch.toString(),
            conferenceSolutionKey: calendar.ConferenceSolutionKey(type: 'hangoutsMeet'),
          ),
        ),
      );

      final createdEvent = await calendarApi.events.insert(
        event,
        'primary',
        conferenceDataVersion: 1,
        sendUpdates: 'all',
      );

      return createdEvent.hangoutLink;
    } catch (e) {
      debugPrint('GoogleMeetService Error: $e');
      rethrow;
    }
  }

  /// Lança o link do Meet no navegador ou app oficial
  Future<void> launchMeeting(String url) async {
    final uri = Uri.parse(url);
    if (await canopyLaunch(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  Future<bool> canopyLaunch(Uri uri) async {
    return await canLaunchUrl(uri);
  }
}
