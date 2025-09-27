// ambulance-tracker/frontend/lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';
import '../services/auth_service.dart';

final logger = Logger();

class LoginScreen extends StatefulWidget {
  final Function(bool)? onLoginSuccess;

  const LoginScreen({super.key, this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    // Untuk testing, isi default dengan kredensial Admin
    _usernameController.text = 'ppidkotamadiun';
    _passwordController.text = 'madiunmajujayasentosa';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _authService.login(
        _usernameController.text,
        _passwordController.text,
      );

      if (!mounted) return;

      // Jika halaman sebelumnya memberi instruksi navigasi:
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        Navigator.pushReplacementNamed(context, args);
      } else {
        // Default fallback ke home jika tidak ada argumen
        widget.onLoginSuccess?.call(user.isAdmin);
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _callEmergency() async {
    const phoneNumber = '112';
    final uri = Uri(scheme: 'tel', path: phoneNumber);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak dapat melakukan panggilan telepon'),
            ),
          );
        }
      }
    } catch (e) {
      logger.e('Error calling emergency number: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terjadi kesalahan saat melakukan panggilan'),
          ),
        );
      }
    }
  }

  Future<void> _launchWhatsApp() async {
    const phoneNumber = '628113577800';
    const message = '';

    // Coba beberapa format URL WhatsApp
    final List<String> whatsappUrls = [
      'whatsapp://send?phone=$phoneNumber&text=$message',
      'https://wa.me/$phoneNumber?text=$message',
      'https://api.whatsapp.com/send/?phone=$phoneNumber&text=$message&type=phone_number&app_absent=0',
    ];

    bool launched = false;

    for (String url in whatsappUrls) {
      try {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          launched = true;
          break;
        }
      } catch (e) {
        logger.e('Error launching $url: $e');
        continue;
      }
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp tidak terinstall atau tidak dapat dibuka'),
        ),
      );
    }
  }

  Future<void> _launchWebsite() async {
    const url = 'https://madiunkota.go.id';

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Tidak dapat membuka website. Pastikan browser terinstall.'),
            ),
          );
        }
      }
    } catch (e) {
      logger.e('Error launching website: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terjadi kesalahan saat membuka website'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final paddingTop = MediaQuery.of(context).padding.top;
    final paddingBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/login.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: screenHeight - paddingTop - paddingBottom,
              ),
              child: IntrinsicHeight(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.05,
                    vertical: 20.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Spacer untuk mendorong card ke tengah
                      const Spacer(flex: 1),

                      // Transform untuk menggeser card sedikit ke atas
                      Transform.translate(
                        offset: const Offset(0, -5),
                        child: Card(
                          elevation: 12,
                          shadowColor: Colors.black26,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Container(
                            width: double.infinity,
                            constraints: BoxConstraints(
                              maxWidth: screenWidth * 0.9,
                            ),
                            padding: EdgeInsets.all(
                              screenWidth < 360 ? 16.0 : 24.0,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white,
                                  Colors.grey.shade50,
                                ],
                              ),
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Logo Madiun
                                  Container(
                                    height: screenWidth < 360 ? 60 : 80,
                                    width: screenWidth < 360 ? 60 : 80,
                                    decoration: const BoxDecoration(
                                      image: DecorationImage(
                                        image: AssetImage(
                                            'assets/images/madiun.png'),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: screenWidth < 360 ? 12 : 16),

                                  // Welcome Text
                                  Text(
                                    'SELAMAT DATANG DI APLIKASI\nPANTAU MADIUN',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: screenWidth < 360 ? 14 : 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      height: 1.3,
                                    ),
                                  ),
                                  SizedBox(height: screenWidth < 360 ? 6 : 8),
                                  Text(
                                    'SILAHKAN LOGIN TERLEBIH DAHULU',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: screenWidth < 360 ? 11 : 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  SizedBox(height: screenWidth < 360 ? 18 : 24),

                                  // Username Field
                                  TextFormField(
                                    controller: _usernameController,
                                    decoration: InputDecoration(
                                      labelText: 'Username',
                                      labelStyle: TextStyle(
                                        fontSize: screenWidth < 360 ? 12 : 14,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.person,
                                        size: screenWidth < 360 ? 18 : 24,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Colors.blue, width: 2),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: screenWidth < 360 ? 12 : 16,
                                        vertical: screenWidth < 360 ? 12 : 16,
                                      ),
                                    ),
                                    style: TextStyle(
                                      fontSize: screenWidth < 360 ? 12 : 14,
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Masukkan username';
                                      }
                                      return null;
                                    },
                                  ),
                                  SizedBox(height: screenWidth < 360 ? 12 : 16),

                                  // Password Field with visibility toggle
                                  TextFormField(
                                    controller: _passwordController,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      labelStyle: TextStyle(
                                        fontSize: screenWidth < 360 ? 12 : 14,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.lock,
                                        size: screenWidth < 360 ? 18 : 24,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isPasswordVisible
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                          size: screenWidth < 360 ? 18 : 24,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isPasswordVisible =
                                                !_isPasswordVisible;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Colors.blue, width: 2),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: screenWidth < 360 ? 12 : 16,
                                        vertical: screenWidth < 360 ? 12 : 16,
                                      ),
                                    ),
                                    style: TextStyle(
                                      fontSize: screenWidth < 360 ? 12 : 14,
                                    ),
                                    obscureText: !_isPasswordVisible,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Masukkan password';
                                      }
                                      return null;
                                    },
                                  ),
                                  SizedBox(height: screenWidth < 360 ? 18 : 24),

                                  // Login and Emergency Call Buttons Row
                                  Row(
                                    children: [
                                      // Login Button
                                      Expanded(
                                        child: SizedBox(
                                          height: screenWidth < 360 ? 45 : 50,
                                          child: ElevatedButton(
                                            onPressed:
                                                _isLoading ? null : _login,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 3,
                                            ),
                                            child: _isLoading
                                                ? SizedBox(
                                                    width: screenWidth < 360
                                                        ? 18
                                                        : 24,
                                                    height: screenWidth < 360
                                                        ? 18
                                                        : 24,
                                                    child:
                                                        const CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : Text(
                                                    'LOGIN',
                                                    style: TextStyle(
                                                      fontSize:
                                                          screenWidth < 360
                                                              ? 14
                                                              : 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                          width: screenWidth < 360 ? 8 : 12),
                                      // Emergency Call Button
                                      Expanded(
                                        child: SizedBox(
                                          height: screenWidth < 360 ? 45 : 50,
                                          child: ElevatedButton(
                                            onPressed: _callEmergency,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 3,
                                            ),
                                            child: Text(
                                              'PANGGIL 112',
                                              style: TextStyle(
                                                fontSize:
                                                    screenWidth < 360 ? 12 : 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: screenWidth < 360 ? 12 : 16),

                                  // Register Link
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pushNamed(context, '/register');
                                    },
                                    child: Text(
                                      'Belum Punya Akun? Silahkan Daftar Terlebih Dahulu',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.w600,
                                        fontSize: screenWidth < 360 ? 11 : 14,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: screenWidth < 360 ? 12 : 16),

                                  // Website Info Container
                                  InkWell(
                                    onTap: _launchWebsite,
                                    child: Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.all(
                                        screenWidth < 360 ? 10 : 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.blue.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.language,
                                            color: Colors.blue,
                                            size: screenWidth < 360 ? 16 : 20,
                                          ),
                                          SizedBox(
                                              width: screenWidth < 360 ? 6 : 8),
                                          Expanded(
                                            child: Text(
                                              'CEK WEBSITE KOTA MADIUN UNTUK INFORMASI TERBARU',
                                              style: TextStyle(
                                                color: Colors.blue,
                                                fontSize:
                                                    screenWidth < 360 ? 10 : 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: screenWidth < 360 ? 10 : 12),

                                  // WhatsApp Contact Container
                                  InkWell(
                                    onTap: _launchWhatsApp,
                                    child: Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.all(
                                        screenWidth < 360 ? 10 : 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.green.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.chat,
                                            color: Colors.green,
                                            size: screenWidth < 360 ? 16 : 20,
                                          ),
                                          SizedBox(
                                              width: screenWidth < 360 ? 6 : 8),
                                          Expanded(
                                            child: Text(
                                              'TERDAPAT KENDALA ? SILAHKAN HUBUNGI KAMI',
                                              style: TextStyle(
                                                color: Colors.green,
                                                fontSize:
                                                    screenWidth < 360 ? 10 : 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Spacer untuk memberikan ruang di bagian bawah
                      const Spacer(flex: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
