import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Meet Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MeetDemoHome(),
    );
  }
}

class MeetDemoHome extends StatefulWidget {
  const MeetDemoHome({super.key});

  @override
  State<MeetDemoHome> createState() => _MeetDemoHomeState();
}

class _MeetDemoHomeState extends State<MeetDemoHome> {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  GoogleSignInAccount? _currentUser;
  String? _meetingUrl;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _initGoogleSignIn();
  }

  Future<void> _initGoogleSignIn() async {
    // Initialize the singleton
    await _googleSignIn.initialize();

    // Listen to authentication events (Sign-In/Sign-Out)
    _googleSignIn.authenticationEvents.listen((event) {
      setState(() {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _currentUser = event.user;
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          _currentUser = null;
          _meetingUrl = null;
        }
      });
    });

    // Attempt to restore previous session
    try {
      await _googleSignIn.attemptLightweightAuthentication();
    } catch (e) {
      debugPrint('Lightweight authentication failed: $e');
    }
  }

  Future<void> _handleSignIn() async {
    try {
      // In 7.2.0+, use authenticate() instead of signIn()
      await _googleSignIn.authenticate();
    } catch (error) {
      debugPrint('Sign in error: $error');
    }
  }

  Future<void> _handleSignOut() => _googleSignIn.signOut();

  Future<void> _createMeeting() async {
    if (_currentUser == null) return;

    setState(() {
      _isCreating = true;
    });

    try {
      // Authorize scopes to get the token
      final scopes = [calendar.CalendarApi.calendarEventsScope];
      final authorization = await _currentUser!.authorizationClient.authorizeScopes(scopes);
      
      final accessToken = authorization.accessToken;

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

      final event = calendar.Event(
        summary: 'Demo Google Meet Meeting',
        description: 'Meeting created via Flutter App',
        start: calendar.EventDateTime(
          dateTime: DateTime.now().add(const Duration(minutes: 10)),
        ),
        end: calendar.EventDateTime(
          dateTime: DateTime.now().add(const Duration(minutes: 40)),
        ),
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
      );

      setState(() {
        _meetingUrl = createdEvent.hangoutLink;
      });
    } catch (error) {
      debugPrint('Error creating meeting: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create meeting: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _launchMeeting() async {
    if (_meetingUrl != null) {
      final url = Uri.parse(_meetingUrl!);
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        debugPrint('Could not launch $_meetingUrl');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Meet Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_currentUser == null) ...[
              const Text('Sign in to create a meeting'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _handleSignIn,
                child: const Text('SIGN IN WITH GOOGLE'),
              ),
            ] else ...[
              Text('Signed in as ${_currentUser!.displayName ?? _currentUser!.email}'),
              const SizedBox(height: 20),
              if (_meetingUrl == null)
                _isCreating
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _createMeeting,
                        child: const Text('CREATE GOOGLE MEET LINK'),
                      )
              else ...[
                const Text('Meeting Created!', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(_meetingUrl!),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _launchMeeting,
                  child: const Text('JOIN MEETING'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => setState(() => _meetingUrl = null),
                  child: const Text('Create Another'),
                ),
              ],
              const SizedBox(height: 40),
              TextButton(
                onPressed: _handleSignOut,
                child: const Text('SIGN OUT'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
