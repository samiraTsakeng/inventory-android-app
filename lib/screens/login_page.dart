import 'package:flutter/material.dart';
import '../services/auth_service.dart';  
import '../utils/storage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final hostController = TextEditingController();
  final dbController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool onlyPassword = false;

  @override
  void initState() {
    super.initState();
    loadSavedData();
  }

  void loadSavedData() async {
    final data = await Storage.getUserData();

    if (data != null) {
      setState(() {
        hostController.text = data['host'] ?? '';
        emailController.text = data['email'] ?? '';
        onlyPassword = true;
      });
    }
  }

  void login() async {
    try {
      final success = await AuthService.login(
        host: hostController.text.trim(),
        db: dbController.text.trim(),
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      if (success) {
        await Storage.saveUserData(
          hostController.text.trim(),
          dbController.text.trim(),
          emailController.text.trim(),
        );
        Navigator.pushReplacementNamed(context, '/adjustment-entry');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Login failed: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                "assets/images/image266622.png", // replace with your real path
                height: 120,
              ),
              Text("Login here", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 5),
              Text("welcome back"),

              SizedBox(height: 20),

              if (!onlyPassword)
                TextField(
                  controller: hostController,
                  decoration: InputDecoration(labelText: "Enter url"),
                ),

              if (!onlyPassword)
                TextField(
                  controller: dbController,
                  decoration: InputDecoration(labelText: "Enter db name"),
                ),

              if (!onlyPassword)
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(labelText: "Enter email"),
                ),

              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(labelText: "Enter Password"),
              ),

              SizedBox(height: 20),

              ElevatedButton(
                onPressed: login,
                child: Text("login"),
              )
            ],
          ),
        ),
      ),
    );
  }
}