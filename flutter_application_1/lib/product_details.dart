import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_page.dart';
import 'dart:math';
final String flaskApiBaseUrl = "http://10.134.68.30:5000";
// final String flaskApiBaseUrl = "http://10.138.149.10:5000";

class ProductDetailsPage extends StatefulWidget {
  final dynamic product;

  const ProductDetailsPage({super.key, required this.product});

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  List<dynamic> relatedProducts = [];
  List<dynamic> collaborativeProducts = [];
  bool _isLiked = false;
  bool _isSaved = false;
  List<HeartAnimation> hearts = [];
  bool _showInitialDialogue = true;

  final Map<String, String> hybridGiftSuggestions = {
    "Clothing, Shoes & Jewelry": "Hybrid gift suggestion: Image (Fashion photo or style inspiration).",
    "Watches": "Hybrid gift suggestion: Video (Timeless moments or unboxing experience).",
    "Beauty": "Hybrid gift suggestion: Video (Beauty tips or self-care tutorial).",
    "Grocery & Gourmet Food": "Hybrid gift suggestion: Video (Recipe tutorial or cooking tips).",
    "Home & Kitchen": "Hybrid gift suggestion: Video (Cooking tutorial or home decor ideas).",
    "Electronics": "Hybrid gift suggestion: Image (Product showcase or feature highlights).",
    "Health & Household": "Hybrid gift suggestion: Video (Wellness tips or calming guide).",
    "Health & Personal Care": "Hybrid gift suggestion: Video (Meditation or wellness tutorial).",
    "Vitamins, Minerals & Supplements": "Hybrid gift suggestion: Video (Health tips or motivational speech).",
    "Medical Supplies & Equipment": "Hybrid gift suggestion: Video (Instructional or usage guide).",
    "Baby Products": "Hybrid gift suggestion: Video (Parenting tips or unboxing experience).",
    "Sports & Outdoors": "Hybrid gift suggestion: Video (Adventure highlights or motivational clips).",
    "Outdoor Recreation": "Hybrid gift suggestion: Image (Scenic views or travel inspiration).",
    "Fitness & Exercise Equipment": "Hybrid gift suggestion: Video (Workout tutorial or fitness challenge).",
    "Computers": "Hybrid gift suggestion: Video (Tech tips or instructional guide).",
    "Wearable Technology": "Hybrid gift suggestion: Video (Product features or tutorial).",
    "Headphones, Earphones & Accessories": "Hybrid gift suggestion: Video (Product demo or unboxing).",
    "Video Games": "Hybrid gift suggestion: Video (Gameplay highlights or tips).",
    "Toys & Games": "Hybrid gift suggestion: Video (Unboxing or play-through highlights).",
    "Drinks": "Hybrid gift suggestion: Video (Recipe tutorial or drink inspiration).",
    "Fresh & Chilled": "Hybrid gift suggestion: Video (Recipe tutorial or serving ideas).",
    "Arts, Crafts & Sewing": "Hybrid gift suggestion: Video (Creative tutorial or inspiration guide).",
    "Musical Instruments, Stage & Studio": "Hybrid gift suggestion: Video (Performance or musical tips).",
    "Travel Accessories": "Hybrid gift suggestion: Video (Travel vlogs or tips).",
    "Luggage": "Hybrid gift suggestion: Video (Travel tips or relaxation guide).",
  };



  String? getProductId() {
    return widget.product['asin'] ?? 
           widget.product['id']??
           _extractAsinFromUrl(widget.product['url']);
  }

  String getProductTitle() {
    return widget.product['title'] ?? 
          widget.product['Product Name'] ?? 
          widget.product['name'] ?? 
          'Unknown Product';
  }

  List<String> getProductImages() {
    if (widget.product["images"] is String) {
      try {
        return List<String>.from(jsonDecode(widget.product["images"]));
      } catch (e) {
        debugPrint("Error parsing images: $e");
        return [];
      }
    } else if (widget.product["images"] is List) {
      return List<String>.from(widget.product["images"]);
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    debugPrint('Product data structure: ${widget.product}'); 
    
    final department = widget.product["department"];
    final bsCategory = widget.product["bs_category"] ?? "unknown";
    if (department != null && department is String) {
      fetchRelatedProducts(department, bsCategory);
    } else {
      debugPrint("Department is missing or invalid in the product data.");
      fetchRelatedProducts("Unknown Department", "unknown category");
    }
    _checkIfLiked();
    _checkIfSaved();
  }

  Future<void> fetchCollaborativeProducts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('User is not authenticated');
      return;
    }

    final url = Uri.parse('$flaskApiBaseUrl/collaborative_recommendations');

    print('Fetching collaborative recommendations for user: ${user.uid}');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': user.uid}),
      );

      if (response.statusCode == 200) {
        final parsedData = jsonDecode(response.body);
        if (parsedData.containsKey('recommendations')) {
          setState(() {
            collaborativeProducts = List<dynamic>.from(parsedData['recommendations']);
          });
        } else {
          print('Key "recommendations" not found in response');
        }
      } else {
        print('Failed to load collaborative recommendations. Status Code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> fetchRelatedProducts(String department, bsCategory) async {
    final url = Uri.parse('$flaskApiBaseUrl/more_related');

    try {
      final requestBody = {
        'department': department,
        'bs_category' : bsCategory,
        'product_name': widget.product["Product Name"], 
      };
      print('Request Body: $requestBody'); 

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        
        String sanitizedJson = response.body.replaceAll('NaN', 'null');

        final Map<String, dynamic> data = jsonDecode(sanitizedJson);

        // Update the state with the filtered products
        setState(() {
          relatedProducts = List<Map<String, dynamic>>.from(data['filtered_products']);
        });
      } else {
        print('Failed to load related products. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching related products: $e');
    }
  }

  Future<void> load_related(String userId, String department) async {
    try {
      final response = await http.post(
        Uri.parse('$flaskApiBaseUrl/more_related'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'department': department,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode != 200) {
        print('load_related failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('load_related error: $e');
      rethrow;
    }
  }

  Future<void> _checkIfLiked() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final productId = getProductId();
    if (productId == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('liked_items')
        .doc(productId)
        .get();

    if (doc.exists) {
      setState(() {
        _isLiked = true;
      });
    }
  }

  Future<void> _checkIfSaved() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final productId = getProductId();
    if (productId == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('saved_items')
        .doc(productId)
        .get();

    if (doc.exists) {
      setState(() {
        _isSaved = true;
      });
    }
  }

  void _likeProduct() async {
    if (!_isLiked) {
      setState(() {
        _isLiked = true;
      });
      _addHeart(); // Animation
      
      try {
        await _toggleLike(); // Backend save
      } catch (e) {
        setState(() => _isLiked = false); // Revert if fails
      }
    }
  }

  Future<void> _toggleLike() async {
    _handleInitialDialogueResponse(true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final productId = getProductId();
    if (productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot like - missing product ID')),
      );
      return;
    }

    try {
      setState(() => _isLiked = !_isLiked);

      if (_isLiked) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('liked_items')
            .doc(productId)
            .set({
          'title': getProductTitle(),
          'name': getProductTitle(),
          'description': widget.product["Description"] ?? '',
          'rating': widget.product["Rating"] ?? 0, 
          'price': widget.product["initial_price"] ?? 0, 
          'department': widget.product["department"] ?? '', 
          'images': getProductImages(),
          'asin': productId,
          'id': productId,
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('liked_items')
            .doc(productId)
            .delete();
      }
    } catch (e, stack) {
      setState(() => _isLiked = !_isLiked); 
      print('Error in _toggleLike: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to ${_isLiked ? 'unlike' : 'like'} product')),
      );
    }
  }

  Future<void> _toggleSave() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final productId = getProductId();
    if (productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot save - missing product ID')),
      );
      return;
    }

    setState(() {
      _isSaved = !_isSaved;
    });

    if (_isSaved) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('saved_items')
          .doc(productId)
          .set({
        'title': getProductTitle(),
        'name': getProductTitle(),
        'description': widget.product["Description"] ?? '',
        'rating': widget.product["Rating"] ?? 0,
        'price': widget.product["initial_price"] ?? 0,
        'department': widget.product["department"] ?? '',
        'images': getProductImages(),
        'id': productId,
        'asin': productId,
      });
    } else {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('saved_items')
          .doc(productId)
          .delete();
    }
  }

  void _addHeart() {
    setState(() {
      hearts.add(HeartAnimation(
        key: UniqueKey(),
        onComplete: () {
          setState(() {
            hearts.removeWhere((heart) => heart.key == heart.key);
          });
        },
      ));
    });
  }

  void _handleInitialDialogueResponse(bool isHelpful) async {
    try {

      final productId = getProductId();
      if (productId == null) {
        throw Exception('''
          Product ID not found. Available fields:
          ${widget.product.keys.join(', ')}
          URL: ${widget.product['url']}
        ''');
      }

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      // Determine endpoint based on user feedback
      final endpoint = isHelpful ? 'like_product' : 'dislike_product';
      final successMessage = isHelpful ? 'Thanks for your feedback!' : 'Sorry to hear that!';

      // Send feedback to server
      final response = await http.post(
        Uri.parse('$flaskApiBaseUrl/$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'product_id': productId,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );

      } else {
        throw Exception('Server responded with status: ${response.statusCode}');
      }
    } catch (e) {

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send feedback: ${e.toString()}')),
        );
      }
      debugPrint('Feedback submission error: $e');
    }
  }

  String? _extractAsinFromUrl(dynamic url) {
    try {
      if (url == null) return null;
      final urlStr = url.toString();
    
      final regex = RegExp(r'(?:/dp/|/gp/product/)([A-Z0-9]{10})');
      final match = regex.firstMatch(urlStr);
      
      if (match == null) {
        debugPrint('Could not extract ASIN from URL: $urlStr');
        return null;
      }
      return match.group(1);
    } catch (e) {
      debugPrint('ASIN extraction error: $e');
      return null;
    }
  }

  void _showHybridGiftExplanation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("What is a Hybrid Gift?"),
          content: const Text(
            "A hybrid gift combines a physical item (like chocolates or flowers) with a personalised digital touch, such as a video, photos, or a custom note. "
            "It’s a unique and memorable way to show you care! \n\n"
            "Tip: Media is exchanged interactively, letting both you and the recipient reveal each other’s digital content for a fun and engaging experience.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSaveConfirmationDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          icon: const Icon(Icons.bookmark, color: Colors.deepPurple),
          title: const Text("Gift Idea Saved"),
          content: const Text(
            "Your gift idea has been saved successfully. You can view it later from the bookmark icon.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final productName = getProductTitle();
    final productRating = widget.product["Rating"] ?? widget.product["rating"] ?? 'N/A';
    final productPrice = widget.product["price"] ?? widget.product["initial_price"] ?? 'N/A';
    final imageUrls = getProductImages();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Product Details"),
        backgroundColor: const Color.fromARGB(255, 176, 146, 227),
        actions: [
          IconButton(
            icon: Icon(
              _isLiked ? Icons.favorite : Icons.favorite_border,
              color: _isLiked ? Colors.red : Colors.white,
            ),
            onPressed: _toggleLike,
          ),
          IconButton(
            icon: Icon(
              _isSaved ? Icons.bookmark : Icons.bookmark_border,
              color: _isSaved ? Colors.blue[300] : Colors.white,
            ),
            onPressed: _toggleSave,
          ),
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            onDoubleTap: () {
              if (!_isLiked) {  // Only trigger if not already liked
                _likeProduct();  // For animation
                _toggleLike();   // For backend save
              }
            },
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: "Product Details"),
                      Tab(text: "More Related"),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Product Details Tab
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                productName,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              if (widget.product["department"] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.info_outline, color: Colors.deepPurple, size: 20),
                                        onPressed: () {
                                          _showHybridGiftExplanation(context);
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          hybridGiftSuggestions[widget.product["department"]] ?? 
                                              "Hybrid gift suggestion: Make this gift extra special with a personalised touch!",
                                          style: const TextStyle(
                                            fontSize: 16, 
                                            fontStyle: FontStyle.italic, 
                                            color: Colors.deepPurple,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 16),
                              if (imageUrls.isNotEmpty) ...[
                                SizedBox(
                                  height: 200,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: imageUrls.length,
                                    itemBuilder: (context, index) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.network(
                                            imageUrls[index],
                                            width: 200,
                                            height: 200,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return const Icon(Icons.broken_image, size: 100, color: Colors.grey);
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              Text("Rating: $productRating"),
                              Text("Department: ${widget.product['department'] ?? 'N/A'}"),
                              Text("Reference Price: £ $productPrice"),
                              const SizedBox(height: 8),
                              const SizedBox(height: 20),
                              Center(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    _toggleSave();
                                    await _showSaveConfirmationDialog(context); 
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatScreen(
                                          showBackButton: true,
                                        ), 
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                                    textStyle: const TextStyle(fontSize: 16),
                                  ),
                                  child: const Text("Send a hybrid gift to your special one"),
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (_showInitialDialogue)
                                SizedBox(
                                  width: MediaQuery.of(context).size.width * 0.9,
                                  child: AlertDialog(
                                    title: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "Is this gift useful?",
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () {
                                            setState(() {
                                              _showInitialDialogue = false;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    content: const Text("Do you find this product helpful for your needs?"),
                                    actions: [
                                      TextButton(
                                        onPressed: () => _handleInitialDialogueResponse(false),
                                        child: const Text("No"),
                                      ),
                                      TextButton(
                                        onPressed: () => _handleInitialDialogueResponse(true),
                                        child: const Text("Yes"),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // More Related Tab
                        ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: relatedProducts.length,
                          itemBuilder: (context, index) {
                            final relatedProduct = relatedProducts[index];
                            final imageUrl = relatedProduct["images"] is String
                                ? (jsonDecode(relatedProduct["images"]) as List).first
                                : (relatedProduct["images"] as List).first;

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: InkWell(
                                onTap: () async {
                                  final user = FirebaseAuth.instance.currentUser;
                                  final userId = user != null ? user.uid : 'unknown_user';
                                  final department = relatedProduct["department"]?.toString() ?? 'Unknown';
                          
                                  await load_related(userId, department);

                                  List<String> imageUrls = [];
                                  if (relatedProduct["images"] is String) {
                                    try {
                                      imageUrls = List<String>.from(jsonDecode(relatedProduct["images"]));
                                    } catch (e) {
                                      print("Error parsing images: $e");
                                      imageUrls = ["https://via.placeholder.com/200"];
                                    }
                                  } else if (relatedProduct["images"] is List) {
                                    imageUrls = List<String>.from(relatedProduct["images"]);
                                  }

                                  final updatedProduct = {
                                    ...relatedProduct,
                                    "images": imageUrls,
                                  };

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProductDetailsPage(product: updatedProduct),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          imageUrl,
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              width: 100,
                                              height: 100,
                                              color: Colors.grey[200],
                                              child: const Icon(Icons.broken_image, color: Colors.grey),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              relatedProduct["Product Name"] ?? relatedProduct["name"] ?? "Unknown Product",
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Rating: ${relatedProduct['Rating'] ?? relatedProduct['rating'] ?? 'N/A'}",
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey,
                                              ),
                                            ),                                           
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Heart animations
          ...hearts.map((heart) => heart).toList(),
        ],
      ),
    );
  }
}

class HeartAnimation extends StatefulWidget {
  final VoidCallback onComplete;

  const HeartAnimation({Key? key, required this.onComplete}) : super(key: key);

  @override
  _HeartAnimationState createState() => _HeartAnimationState();
}

class _HeartAnimationState extends State<HeartAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _positionAnimation;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2), weight: 40),
        TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 60),
      ],
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );

    _positionAnimation = Tween<double>(begin: 0.0, end: -100.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double leftPosition = 50 + _random.nextDouble() * (MediaQuery.of(context).size.width - 100);

    return Positioned(
      left: leftPosition,
      bottom: 100,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _positionAnimation.value),
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: const Icon(
                  Icons.favorite,
                  color: Colors.red,
                  size: 40,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class DebugView extends StatelessWidget {
  final String userId;

  const DebugView({super.key, required this.userId});

  Future<Map<String, dynamic>> _fetchDebugData() async {
    final response = await http.get(
      Uri.parse('$flaskApiBaseUrl/debug_user/$userId'),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load debug data');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recommendation Debug'),
        backgroundColor: const Color.fromARGB(255, 176, 146, 227),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchDebugData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return const Center(child: Text('No debug data available'));
          }

          final data = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Preferences', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('Likes: ${data['preferences']['likes'].join(', ') ?? 'None'}'),
                        Text('Dislikes: ${data['preferences']['dislikes'].join(', ') ?? 'None'}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Recommendation Logic', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...(data['recommendation_reasons'] as List?)?.map((reason) => 
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(reason['product_id'] ?? 'Unknown'),
                      subtitle: Text(reason['reason'] ?? 'No reason provided'),
                    ),
                  )
                ) ?? [const Text('No recommendation data available')],
              ],
            ),
          );
        },
      ),
    );
  }
}