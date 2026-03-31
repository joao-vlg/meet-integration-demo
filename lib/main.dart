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
  final TextEditingController _recipientController = TextEditingController();
  GoogleSignInAccount? _currentUser;
  String? _meetingUrl;
  bool _isCreating = false;

  bool _isValidEmail(String email) {
    return RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
        .hasMatch(email);
  }

  @override
  void initState() {
    super.initState();
    _initGoogleSignIn();
  }

  Future<void> _initGoogleSignIn() async {
    // Initialize the singleton with the serverClientId for Android
    await _googleSignIn.initialize(
      serverClientId: '771127470041-50p3s939ji92it8qussgvkmfhad2596s.apps.googleusercontent.com',
    );

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

    final email = _recipientController.text.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, insira um e-mail válido para a chamada.')),
      );
      return;
    }

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
        summary: 'Chamada do Google Meet',
        description: 'Chamada instantânea iniciada via App',
        start: calendar.EventDateTime(
          dateTime: DateTime.now(),
        ),
        end: calendar.EventDateTime(
          dateTime: DateTime.now().add(const Duration(hours: 1)),
        ),
        attendees: [
          calendar.EventAttendee(email: email),
        ],
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
        sendUpdates: 'all', // Notifica o destinatário por e-mail
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
              if (_meetingUrl == null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: TextField(
                    controller: _recipientController,
                    decoration: const InputDecoration(
                      labelText: 'E-mail do Destinatário',
                      hintText: 'exemplo@gmail.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(height: 20),
                _isCreating
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: _createMeeting,
                        icon: const Icon(Icons.call),
                        label: const Text('INICIAR CHAMADA NO GOOGLE MEET'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
              ] else ...[
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
