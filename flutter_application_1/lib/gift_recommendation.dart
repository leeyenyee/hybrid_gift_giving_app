import 'package:flutter/material.dart';
import 'package:flutter_application_1/savedGiftIdea.dart';
import 'dart:convert';
import 'product_details.dart';
import 'package:http/http.dart' as http;
import 'liked_item.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
final String flaskApiBaseUrl = "http://10.134.68.30:5000";
// final String flaskApiBaseUrl = "http://10.138.149.10:5000";

class GiftTab extends StatefulWidget {
  final String? initialOccasion;
  final bool showFilterPanel; 
  final bool showBackButton; 

  const GiftTab({
    super.key,
    this.initialOccasion,
    this.showFilterPanel = false, 
    this.showBackButton = true, 
  });

  @override
  _GiftTabState createState() => _GiftTabState();
}

class _GiftTabState extends State<GiftTab> {
  List<dynamic> recommendedGifts = [];
  List<dynamic> displayedProducts = [];
  List<String> selectedOccasions = [];
  String? selectedGender;
  String? selectedAgeRange;
  String? selectedPriceRange;
  int _offset = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false; 
  bool showBackButton = false;
  final List<String> _recentDepartments = [];
  final List<String> occasions = ["Birthday", "Anniversary", "Baby & Expecting", "Father's Day", "Mother's Day", "Christmas", "Friendship Day", "New Year"];
  final List<String> genders = ["Male", "Female"];
  final List<String> ageRanges = ["0-14", "15-20", "21-30", "31-40", "41+"];
  final List<String> priceRanges = ["0-50", "51-100", "100+"];
  final List<String> sortByRateOptions = ["Highest Rated", "Lowest Rated"];
  final List<String> sortByPopOptions = ["Highest Popularity", "Lowest Popularity"];
  String? selectedSortByRating;
  String? selectedSortByPop;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController(); //back to top button
  bool _showBackToTopButton = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();

    if (widget.initialOccasion != null) {
      selectedOccasions = [widget.initialOccasion!];
    }

    if (widget.showFilterPanel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFilterPanel();
      });
    }

    _initializeRecommendations();

    // Listen to scroll events to show/hide the "Back to Top" button
    _scrollController.addListener(() {
      _safeSetState(() {
        _showBackToTopButton = _scrollController.offset > 200;
      });
    });
  }

  @override
  void dispose() {
    _isDisposed = true; 
    _scrollController.dispose();
    super.dispose();
  }

  // Helper method to safely call setState
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  Future<void> _initializeRecommendations() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final likedItemsSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('liked_items')
        .get();

    final likedItems = likedItemsSnapshot.docs.map((doc) => doc.data()).toList();

    if (_recentDepartments.isEmpty && likedItems.isEmpty) {
      await recommend_random_products();
    } else {
      await fetchPersonalizedRecommendations();
    }
  }

  Future<void> recommend_random_products() async {
    final url = Uri.parse('$flaskApiBaseUrl/recommend_random_products');

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        _safeSetState(() {
          recommendedGifts = jsonDecode(response.body)['recommend_random_products'];
          displayedProducts = List.from(recommendedGifts);
          _isLoading = false;
        });
      } else {
        _safeSetState(() {
          recommendedGifts = [];
          displayedProducts = [];
          _isLoading = false;
        });
        print('Failed to load recommend_random_products');
      }
    } catch (e) {
      _safeSetState(() {
        _isLoading = false;
      });
      print('Error: $e');
    }
  }

  Future<void> fetchPersonalizedRecommendations() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      // Fetch liked items from Firestore
      final likedItemsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('liked_items')
          .get();

      final likedItems = likedItemsSnapshot.docs.map((doc) => doc.data()).toList();
      final likedDepartments = likedItems.map((item) => item['department'] as String).toList();
      final departments = <dynamic>{..._recentDepartments, ...likedDepartments}.toList();

      // Fetch personalized recommendations from the backend
      final response = await http.post(
        Uri.parse('$flaskApiBaseUrl/recommend'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'occasion': selectedOccasions.isNotEmpty ? selectedOccasions : null,
          'gender': selectedGender,
          'age_range': selectedAgeRange,
          'price_range': selectedPriceRange,
          'limit': 40, // Request more to allow for client-side filtering
          'offset': _offset,
          'recent_departments': departments,
          'exploration_rate': 0.2, // Lower exploration rate for stricter filtering
        }),
      );

      if (response.statusCode == 200) {
        final newProducts = jsonDecode(response.body)['recommendations'];
        
        // Client-side secondary filtering
        final filteredProducts = newProducts.where((product) {
          // Ensure gender matches if specified
          if (selectedGender != null) {
            final title = product['title'].toString().toLowerCase();
            if (selectedGender == 'Women' && title.contains('men')) {
              return false;
            }
            if (selectedGender == 'Men' && title.contains('women')) {
              return false;
            }
          }
          return true;
        }).toList();

        // Apply exploration/exploitation balance
        filteredProducts.shuffle();
        final personalizedProducts = filteredProducts
            .where((product) => departments.contains(product['department']))
            .toList();

        const explorationRate = 0.3;
        final explorationCount = (filteredProducts.length * explorationRate).round();
        final explorationProducts = filteredProducts.take(explorationCount).toList();
        final combinedProducts = <dynamic>{...personalizedProducts, ...explorationProducts}.toList();

        _safeSetState(() {
          recommendedGifts = combinedProducts;
          displayedProducts = List.from(recommendedGifts);
          _isLoading = false;
        });
      } else {
        _safeSetState(() {
          _isLoading = false;
        });
        print('Failed to load personalized recommendations');
      }
    } catch (e) {
      _safeSetState(() {
        _isLoading = false;
      });
      print('Error: $e');
    }
  }

  Future<void> fetchRecommendations({bool loadMore = false}) async {
    if (loadMore && _isLoadingMore) return; // Prevent multiple simultaneous load more requests
    if (!loadMore && _isLoading) return; // Prevent multiple simultaneous initial load requests

    if (loadMore) {
      _safeSetState(() {
        _isLoadingMore = true;
      });
    } else {
      _safeSetState(() {
        _isLoading = true;
      });
    }

    if (!loadMore && selectedOccasions.isEmpty && selectedGender == null &&
        selectedAgeRange == null && selectedPriceRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one filter.")),
      );
      _safeSetState(() {
        _isLoading = false;
      });
      return;
    }

    final url = Uri.parse('$flaskApiBaseUrl/recommend');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'occasion': selectedOccasions.isNotEmpty ? selectedOccasions : null,
          'gender': selectedGender,
          'age_range': selectedAgeRange,
          'price_range': selectedPriceRange,
          'limit': 20,
          'offset': loadMore ? _offset : 0,
          'recent_departments': loadMore ? _recentDepartments : [],
        }),
      );

      if (response.statusCode == 200) {
        final newProducts = jsonDecode(response.body)['recommendations'];
        _safeSetState(() {
          if (loadMore) {
            displayedProducts.addAll(newProducts); // Append items directly to displayedProducts
            _offset += newProducts.length as int; // Cast to int
            _hasMore = newProducts.isNotEmpty;
            _isLoadingMore = false;
          } else {
            displayedProducts = newProducts; // Replace items for a fresh load
            _offset = displayedProducts.length;
            _hasMore = newProducts.isNotEmpty;
            _isLoading = false;
          }
        });
      } else {
        _safeSetState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        print('Failed to load recommendations');
      }
    } catch (e) {
      _safeSetState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      print('Error: $e');
    }
  }

  Future<void> sortTopRated() async {
    _safeSetState(() {
      displayedProducts.sort((a, b) => (b['Rating'] as double).compareTo(a['Rating'] as double));
    });
  }

  Future<void> sortTopPopular() async {
    _safeSetState(() {
      displayedProducts.sort((a, b) {
        // Convert 'Popularity' from String to int
        final popularityA = int.tryParse(a['Popularity'].toString()) ?? 0;
        final popularityB = int.tryParse(b['Popularity'].toString()) ?? 0;

        // Compare the integer values
        return popularityB.compareTo(popularityA);
      });
    });
  }

  void _showFilterPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.8, 
              child: SingleChildScrollView( 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilterSection("Occasions", occasions, selectedOccasions, setModalState),
                    _buildFilterSection("Gender", genders, selectedGender, setModalState, isSingleSelect: true),
                    _buildFilterSection("Age Range", ageRanges, selectedAgeRange, setModalState, isSingleSelect: true),
                    _buildFilterSection("Price Range", priceRanges, selectedPriceRange, setModalState, isSingleSelect: true),
                    _buildFilterSection("Sort by Rating", sortByRateOptions, selectedSortByRating, setModalState, isSingleSelect: true),
                    _buildFilterSection("Sort by Popularity", sortByPopOptions, selectedSortByPop, setModalState, isSingleSelect: true),
                    const SizedBox(height: 20), 
                    ElevatedButton(
                      onPressed: () {
                        
                        print("Selected Occasions: $selectedOccasions");
                        print("Selected Gender: $selectedGender");
                        print("Selected Age Range: $selectedAgeRange");
                        print("Selected Price Range: $selectedPriceRange");
                        print("Selected Sort by Rating: $selectedSortByRating");
                        print("Selected Sort by Popularity: $selectedSortByPop");

                        // Apply sorting if selected
                        if (selectedSortByRating == "Highest Rated") {
                          sortTopRated();
                        }
                        if (selectedSortByPop == "Highest Popularity") {
                          sortTopPopular();
                        }

                        // Check if at least one main filter is selected (occasions, gender, age range, price range)
                        final isMainFilterSelected = selectedOccasions.isNotEmpty ||
                            selectedGender != null ||
                            selectedAgeRange != null ||
                            selectedPriceRange != null;

                        // If no main filter is selected and no sorting option is selected, show the message
                        if (!isMainFilterSelected &&
                            selectedSortByRating == null &&
                            selectedSortByPop == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please select at least one filter.")),
                          );
                        } else {
                          // Fetch recommendations and close the filter panel
                          fetchRecommendations();
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("APPLY FILTER"),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterSection(String title, List<String> options, dynamic selectedValue, StateSetter setModalState, {bool isSingleSelect = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8,
          children: options.map((option) {
            final bool isSelected = isSingleSelect ? selectedValue == option : selectedValue.contains(option);
            return GestureDetector(
              onTap: () {
                setModalState(() {
                  if (isSingleSelect) {
                    if (title == "Gender") {
                      selectedGender = selectedGender == option ? null : option;
                    } else if (title == "Age Range") {
                      selectedAgeRange = selectedAgeRange == option ? null : option;
                    }  else if (title == "Price Range") {
                      selectedPriceRange = selectedPriceRange == option ? null : option;
                    } else if (title == "Sort by Rating") {
                      selectedSortByRating = selectedSortByRating == option ? null : option;
                    }
                    else if (title == "Sort by Popularity") {
                      selectedSortByPop = selectedSortByPop == option ? null : option;
                    }
                  } else {
                    if (selectedOccasions.contains(option)) {
                      selectedOccasions.remove(option);
                    } else {
                      selectedOccasions.add(option);
                    }
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: isSelected ? Colors.deepPurple : Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: isSelected ? Colors.deepPurple.withOpacity(0.2) : Colors.transparent,
                ),
                child: Text(option, style: const TextStyle(fontSize: 14)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  void _trackDepartment(String department) {
    _safeSetState(() {
      if (!_recentDepartments.contains(department)) {
        _recentDepartments.add(department);
      }
    });
  }

  // Function to scroll to the top
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  // Function to refresh recommendations
  Future<void> _refreshRecommendations() async {
    _safeSetState(() {
      displayedProducts.clear();
      _offset = 0; 
      _hasMore = true; 
    });
    await recommend_random_products(); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color.fromARGB(255, 176, 146, 227),
        title: const Text("Gift Choices"),
        leading: widget.showBackButton
            ? null 
            : Container(), 
        automaticallyImplyLeading: widget.showBackButton,
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark),
            tooltip: "Saved Gift Idea",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SavedGiftIdeasPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: "Liked Items",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LikedItemsPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: "Filter Gifts",
            onPressed: _showFilterPanel,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshRecommendations,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator()) 
            : displayedProducts.isEmpty
                ? const Center(child: Text("No recommendations yet. Apply a filter."))
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: displayedProducts.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == displayedProducts.length) {
                              return _isLoadingMore
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(child: CircularProgressIndicator()),
                                )
                              : Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: ElevatedButton(
                                      onPressed: _hasMore ? () => fetchRecommendations(loadMore: true) : null,
                                      child: const Text("Load More"),
                                    ),
                                  ),
                                );
                            }

                            final gift = displayedProducts[index];
                            final imageUrl = gift["images"] is String
                                ? (jsonDecode(gift["images"]) as List).first
                                : (gift["images"] as List).first;

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              child: InkWell(
                                onTap: () {
                                  _trackDepartment(gift["department"]);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProductDetailsPage(product: gift),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Product Image
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

                                      // Product Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Product Title
                                            Text(
                                              gift["Product Name"] ?? "Unknown Product",
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),

                                            // Rating and Department
                                            Text(
                                              "Rating: ${gift['Rating'] ?? 'N/A'} | Department: ${gift['department'] ?? 'N/A'} | Reference  Price: £ ${gift['price'] ?? 'N/A'}",
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
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
                      ),
                    ],
                  ),
        ),
      floatingActionButton: _showBackToTopButton
          ? FloatingActionButton(
              onPressed: _scrollToTop,
              child: const Icon(Icons.arrow_upward),
            )
          : null,
    );
  }
}