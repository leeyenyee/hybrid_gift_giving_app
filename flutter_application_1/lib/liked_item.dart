import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'product_details.dart';

class LikedItemsPage extends StatefulWidget {
  const LikedItemsPage({super.key});

  @override
  _LikedItemsPageState createState() => _LikedItemsPageState();
}

class _LikedItemsPageState extends State<LikedItemsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String flaskApiBaseUrl = "http://10.134.68.30:5000";
  // final String flaskApiBaseUrl = "http://10.138.149.10:5000";
  
  List<Map<String, dynamic>> _likedItems = [];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchLikedItems();
  }

  Future<void> _fetchLikedItems() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    final User? user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('liked_items')
          .orderBy('created_at', descending: true)
          .get();

      setState(() {
          _likedItems = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          debugPrint("Fetched saved gift idea: $data");
          return {
            'id': doc.id,
            'name': data['name'] ?? 'No Name',
            'description': data['description'] ?? 'No Description',
            'images': data['images'] ?? [],
            'rating': data['rating'] ?? 0,
            'department': data['department'] ?? 'Unknown',
          };
        }).toList();
      });

      await _sendLikedItemsToBackend(user.uid);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching liked items: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
    }

  Future<void> _sendLikedItemsToBackend(String userId) async {
    final List<String> likedItemNames = _likedItems.map((item) => item['name'].toString()).toList();

    final response = await http.post(
      Uri.parse('$flaskApiBaseUrl/update_likes'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "user_id": userId,
        "liked_items": likedItemNames,
      }),
    );
  }

  Future<void> _removeLikedItem(String itemId) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('liked_items')
          .doc(itemId)
          .delete();

      _fetchLikedItems(); 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing item: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liked Items')),
      body: RefreshIndicator(
        onRefresh: _fetchLikedItems,
        child: Column(
          children: [
            if (_isLoading)
              const LinearProgressIndicator(),
            Expanded(
              child: _likedItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No Liked Items yet.'),
                          TextButton(
                            onPressed:  _fetchLikedItems,
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _likedItems.length,
                      itemBuilder: (context, index) {
                        final item = _likedItems[index];
                        return ListTile(
                          leading: Icon(Icons.favorite, color: Colors.red),
                          title: Text(item['name'] ?? 'No Name'),
                          onTap: () {
                            if (item.containsKey('name') && item.containsKey('images')) {
                              final productData = {
                                ...item,
                                'title': item['name'] ?? item['title'], 
                                'Product Name': item['name'] ?? item['title'], 
                              };
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailsPage(product: productData),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Error: Invalid item data.")),
                              );
                            }
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              final itemId = item['id'];
                              if (itemId != null) {
                                _removeLikedItem(itemId);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Error: Item ID is missing.")),
                                );
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}