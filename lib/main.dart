import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'call_service.dart';
import 'google_meet_service.dart';
import 'jitsi_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MeetDemoApp());
}

class MeetDemoApp extends StatelessWidget {
  const MeetDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UFF Meet Integration PoC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MeetDemoHome(),
    );
  }
}

// =============================================================================
// Tela Principal
// =============================================================================

class MeetDemoHome extends StatefulWidget {
  const MeetDemoHome({super.key});

  @override
  State<MeetDemoHome> createState() => _MeetDemoHomeState();
}

class _MeetDemoHomeState extends State<MeetDemoHome> {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final TextEditingController _recipientController = TextEditingController();
  GoogleSignInAccount? _currentUser;
  String? _meetingUrl; // Usado apenas para chamadas Google Meet
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
    await _googleSignIn.initialize(
      serverClientId: '222693628192-qefmvcdmbtsub02al4802v78gs0il8gk.apps.googleusercontent.com',
    );

    _googleSignIn.authenticationEvents.listen((event) async {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        final user = event.user;

        try {
          final dynamic auth = await (user as dynamic).authentication;
          String? idToken;
          String? accessToken;

          try { idToken = auth.idToken; } catch (_) {}
          try { accessToken = auth.accessToken; } catch (_) {}
          if (idToken == null) { try { idToken = auth.id_token; } catch (_) {} }
          if (accessToken == null) { try { accessToken = auth.access_token; } catch (_) {} }

          if (idToken != null || accessToken != null) {
            final AuthCredential credential = GoogleAuthProvider.credential(
              accessToken: accessToken,
              idToken: idToken,
            );
            await FirebaseAuth.instance.signInWithCredential(credential);
            debugPrint('Firebase Auth: ${FirebaseAuth.instance.currentUser?.uid}');
          }
        } catch (e) {
          debugPrint('Firebase Auth Error: $e');
        }

        setState(() {
          _currentUser = user;
          CallService().initialize();
          CallService().registerUser(_currentUser!.email);
        });
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        setState(() {
          _currentUser = null;
          _meetingUrl = null;
          CallService().dispose();
        });
      }
    });

    try {
      await _googleSignIn.attemptLightweightAuthentication();
    } catch (e) {
      debugPrint('Sessão prévia não encontrada.');
    }
  }

  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.authenticate();
    } catch (error) {
      debugPrint('Sign in error: $error');
    }
  }

  Future<void> _handleSignOut() => _googleSignIn.signOut();

  // ---------------------------------------------------------------------------
  // Inicia a chamada
  // ---------------------------------------------------------------------------

  Future<void> _startMeeting(String provider) async {
    if (_currentUser == null) return;

    final email = _recipientController.text.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, insira um e-mail válido para a chamada.')),
      );
      return;
    }

    setState(() { _isCreating = true; });

    try {
      if (provider == 'meet') {
        // --- Google Meet: cria link e sinaliza ---
        final link = await GoogleMeetService().createMeeting(_currentUser!, email);
        if (link == null) throw 'Google Meet não conseguiu gerar o link (Limites da Instituição?)';

        await CallService().startCall(_currentUser!.email, email, link, provider);
        setState(() { _meetingUrl = link; });

      } else if (provider == 'jitsi') {
        // --- Jitsi: gera sala, sinaliza e abre a tela "Chamando..."
        final roomName = JitsiService().generateRoomName();
        await CallService().startCall(_currentUser!.email, email, roomName, provider);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CallingScreen(
                recipientEmail: email,
                callerDisplayName: _currentUser!.displayName ?? 'Usuário UFF',
                callerEmail: _currentUser!.email,
                roomName: roomName,
              ),
            ),
          );
        }
      }
    } catch (error) {
      debugPrint('Erro ao criar chamada: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $error')),
        );
      }
    } finally {
      if (mounted) setState(() { _isCreating = false; });
    }
  }

  // Reentrar em chamada Google Meet já criada
  void _launchMeetMeeting() async {
    if (_meetingUrl == null) return;
    await GoogleMeetService().launchMeeting(_meetingUrl!);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UFF Meet Pro'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_currentUser == null) ...[
              const Text('Conecte-se para iniciar chamadas'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _handleSignIn,
                child: const Text('SIGN IN WITH GOOGLE'),
              ),
            ] else ...[
              const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
              const SizedBox(height: 10),
              Text('Logado como: ${_currentUser!.displayName}'),
              Text(_currentUser!.email, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 30),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: TextField(
                  controller: _recipientController,
                  decoration: const InputDecoration(
                    labelText: 'E-mail do Destinatário',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (_meetingUrl == null) ...[
                if (_isCreating)
                  const CircularProgressIndicator()
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // BOTÃO GOOGLE MEET
                      Column(
                        children: [
                          IconButton.filled(
                            onPressed: () => _startMeeting('meet'),
                            icon: const Icon(Icons.video_call),
                            iconSize: 32,
                            style: IconButton.styleFrom(backgroundColor: Colors.blue),
                          ),
                          const Text('Google Meet', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(width: 40),
                      // BOTÃO JITSI (CHAMADA DE VOZ)
                      Column(
                        children: [
                          IconButton.filled(
                            onPressed: () => _startMeeting('jitsi'),
                            icon: const Icon(Icons.phone),
                            iconSize: 32,
                            style: IconButton.styleFrom(backgroundColor: Colors.green),
                          ),
                          const Text('Chamada de Voz', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
              ] else ...[
                const Text('Chamada Meet em Andamento!', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _launchMeetMeeting,
                  icon: const Icon(Icons.video_chat),
                  label: const Text('REENTRAR NO MEET'),
                ),
                TextButton(
                  onPressed: () => setState(() => _meetingUrl = null),
                  child: const Text('Nova Chamada'),
                ),
              ],

              const SizedBox(height: 40),
              TextButton(
                onPressed: _handleSignOut,
                child: const Text('LOGOUT'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Tela "Chamando..." — exibida para o remetente enquanto aguarda resposta
// =============================================================================

class CallingScreen extends StatefulWidget {
  final String recipientEmail;
  final String callerDisplayName;
  final String callerEmail;
  final String roomName;

  const CallingScreen({
    super.key,
    required this.recipientEmail,
    required this.callerDisplayName,
    required this.callerEmail,
    required this.roomName,
  });

  @override
  State<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends State<CallingScreen> with TickerProviderStateMixin {
  // Animação de pulso
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  // Timer de exibição (cronômetro visual)
  Timer? _displayTimer;
  int _secondsElapsed = 0;

  // Listener do estado da chamada
  StreamSubscription<CallState>? _callStateSubscription;

  // Flag para evitar double-pop
  bool _navigationHandled = false;

  @override
  void initState() {
    super.initState();

    // Configura animação pulsante (círculo que respira)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Cronômetro visual
    _displayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });

    // Escuta o resultado da chamada
    _callStateSubscription = CallService().callStateStream?.listen(_onCallStateChanged);
  }

  // ---------------------------------------------------------------------------
  // Reação ao estado da chamada
  // ---------------------------------------------------------------------------

  void _onCallStateChanged(CallState state) {
    if (!mounted || _navigationHandled) return;

    switch (state) {
      case CallState.connected:
        _handleNavigation(() {
          // Remetente entra na sala Jitsi
          JitsiService().joinMeeting(
            roomName: widget.roomName,
            userDisplayName: widget.callerDisplayName,
            userEmail: widget.callerEmail,
          );
        });
        break;

      case CallState.declined:
        _handleNavigation(() {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chamada recusada pelo destinatário.')),
          );
        });
        break;

      case CallState.timeout:
        _handleNavigation(() {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sem resposta. Tente novamente.')),
          );
        });
        break;

      case CallState.cancelled:
        _handleNavigation(null);
        break;

      default:
        break;
    }
  }

  /// Garante que o pop aconteça uma única vez e executa [afterPop] em seguida.
  void _handleNavigation(VoidCallback? afterPop) {
    if (_navigationHandled) return;
    _navigationHandled = true;
    Navigator.of(context).pop();
    afterPop?.call();
  }

  // ---------------------------------------------------------------------------
  // Cancelar chamada (botão vermelho ou botão de voltar)
  // ---------------------------------------------------------------------------

  Future<void> _cancelCall() async {
    if (_navigationHandled) return;
    await CallService().cancelCall();
    // O cancelCall() emite CallState.cancelled, que é capturado por
    // _onCallStateChanged e faz o pop. Não chamamos Navigator.pop() aqui.
  }

  // ---------------------------------------------------------------------------
  // Formatação do cronômetro
  // ---------------------------------------------------------------------------

  String get _elapsedDisplay {
    final mins = _secondsElapsed ~/ 60;
    final secs = _secondsElapsed % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _pulseController.dispose();
    _displayTimer?.cancel();
    _callStateSubscription?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Impede voltar sem cancelar a chamada
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              // --- Anel pulsante + ícone de telefone ---
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Anel externo (mais transparente)
                      Transform.scale(
                        scale: _pulseScale.value * 1.35,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF2ECC71)
                                .withValues(alpha: _pulseOpacity.value * 0.25),
                          ),
                        ),
                      ),
                      // Anel médio
                      Transform.scale(
                        scale: _pulseScale.value * 1.15,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF2ECC71)
                                .withValues(alpha: _pulseOpacity.value * 0.4),
                          ),
                        ),
                      ),
                      // Círculo principal
                      Container(
                        width: 130,
                        height: 130,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF2ECC71),
                        ),
                        child: const Icon(
                          Icons.phone,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 40),

              // --- Destinatário ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  widget.recipientEmail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Chamando...',
                style: TextStyle(
                  color: Color(0xFF2ECC71),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                _elapsedDisplay,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                ),
              ),

              const Spacer(flex: 3),

              // --- Botão de encerrar/cancelar ---
              GestureDetector(
                onTap: _cancelCall,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.shade600,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),

              const SizedBox(height: 52),
            ],
          ),
        ),
      ),
    );
  }
}
