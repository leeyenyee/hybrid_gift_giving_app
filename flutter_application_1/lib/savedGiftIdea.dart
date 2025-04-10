import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'product_details.dart';

class SavedGiftIdeasPage extends StatefulWidget {
  const SavedGiftIdeasPage({super.key});

  @override
  SavedGiftIdeasPageState createState() => SavedGiftIdeasPageState();
}

class SavedGiftIdeasPageState extends State<SavedGiftIdeasPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String flaskApiBaseUrl = "http://10.134.68.30:5000"; 
  // final String flaskApiBaseUrl = "http://10.138.149.10:5000";

  List<Map<String, dynamic>> _savedItems = [];
  List<String> _recommendedItems = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchSavedItems();
  }

  Future<void> _fetchSavedItems() async {
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
          .collection('saved_items')
          .get();

      setState(() {
        _savedItems = snapshot.docs.map((doc) {
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

      await _sendSavedItemsToBackend(user.uid);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching saved items: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendSavedItemsToBackend(String userId) async {
    final List<String> savedItemNames = _savedItems.map((item) => item['name'].toString()).toList();

    final response = await http.post(
      Uri.parse('$flaskApiBaseUrl/update_saved'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "user_id": userId,
        "saved_items": savedItemNames,
      }),
    );
  }

  Future<void> _removeSavedItem(String itemId) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('saved_items')
          .doc(itemId)
          .delete();

      _fetchSavedItems(); 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing item: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Gift Ideas')),
      body: RefreshIndicator(
        onRefresh: _fetchSavedItems,
        child: Column(
          children: [
            if (_isLoading)
              const LinearProgressIndicator(),
            Expanded(
              child: _savedItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No saved gift ideas yet.'),
                          TextButton(
                            onPressed: _fetchSavedItems,
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _savedItems.length,
                      itemBuilder: (context, index) {
                        final item = _savedItems[index];
                        return ListTile(
                          leading: Icon(Icons.bookmark_added, color: Colors.blue[300]),
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
                                _removeSavedItem(itemId);
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
            if (_recommendedItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    const Text('Recommended Items:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ..._recommendedItems.map((item) => ListTile(
                          leading: const Icon(Icons.star, color: Colors.blue),
                          title: Text(item),
                        )),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}