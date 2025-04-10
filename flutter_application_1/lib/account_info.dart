import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AccountInfoPage extends StatefulWidget {
  const AccountInfoPage({super.key});

  @override
  State<AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<AccountInfoPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  String? _profileImageUrl;
  bool _isDisposed = false; 

  @override
  void dispose() {
    _isDisposed = true; 
    super.dispose();
  }

  // Helper method to safely call setState
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    if (user == null || _isDisposed) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (!_isDisposed && doc.exists && doc.data()!.containsKey('profileImageUrl')) {
        _safeSetState(() {
          _profileImageUrl = doc['profileImageUrl'];
        });
      }
    } catch (e) {
      if (!_isDisposed) {
        debugPrint('Error loading profile image: $e');
      }
    }
  }

  Future<void> _uploadImage(File imageFile) async {
    if (user == null || _isDisposed) return;

    try {
      final String? imgurUrl = await uploadToImgur(imageFile);

      if (!_isDisposed && imgurUrl != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .set({'profileImageUrl': imgurUrl}, SetOptions(merge: true));

        _safeSetState(() {
          _profileImageUrl = imgurUrl;
        });
      }
    } catch (e) {
      if (!_isDisposed) {
        debugPrint('Error uploading profile picture: $e');
      }
    }
  }

  Future<void> _pickImage() async {
    if (_isDisposed) return;

    final ImagePicker picker = ImagePicker();
    final XFile? pickedImage = await showDialog<XFile>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose an option'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () async {
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                  if (!_isDisposed) {
                    Navigator.pop(context, image);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () async {
                  final XFile? image = await picker.pickImage(source: ImageSource.camera);
                  if (!_isDisposed) {
                    Navigator.pop(context, image);
                  }
                },
              ),
            ],
          ),
        );
      },
    );

    if (!_isDisposed && pickedImage != null) {
      final File imageFile = File(pickedImage.path);
      await _uploadImage(imageFile);
    }
  }

  Future<String?> uploadToImgur(File file) async {
    if (_isDisposed) return null;

    final url = Uri.parse('https://api.imgur.com/3/image');
    final request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Client-ID f23175c3a065c42';
    request.files.add(await http.MultipartFile.fromPath('image', file.path));

    try {
      final response = await request.send();
      if (_isDisposed) return null;

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonResponse = jsonDecode(responseData);
        return jsonResponse['data']['link'];
      } else {
        debugPrint("Failed to upload to Imgur: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      if (!_isDisposed) {
        debugPrint("Imgur upload error: $e");
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? email = user?.email;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 176, 146, 227),
        title: const Text('Account Info'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundImage: _profileImageUrl != null
                  ? NetworkImage(_profileImageUrl!)
                  : const AssetImage('default_avatar.png') as ImageProvider,
            ),
            const SizedBox(height: 20),
            Text(
              email ?? 'No email available',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              'Welcome to your account page!',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickImage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 176, 146, 227),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text(
                'Edit Profile',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}