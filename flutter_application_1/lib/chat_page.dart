import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';


class _ChatScreenState extends State<ChatScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _addContactController = TextEditingController();
  File? selectedMedia;
  String? mediaType;
  bool _isLoading = true; 
  User? currentUser;
  String? selectedContact;
  List<Map<String, dynamic>> contacts = [];
  bool showBackButton = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser(); 
  }


  void _loadCurrentUser() async {
    currentUser = _auth.currentUser;
    if (currentUser != null) {
      _loadContacts();
    }

    setState(() {
      _isLoading = false; 
    });
  }

  void _loadContacts() async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(currentUser!.uid).get();
      if (userDoc.exists) {
        List<dynamic> contactList = userDoc['contacts'] ?? [];
        print("Fetched contacts: $contactList");

        // Fetch all existing messages sent to the current user concurrently
        var sentMessagesSnapshotFuture = _firestore
            .collection('chats')
            .where('participants', arrayContains: currentUser!.email)
            .get();

        QuerySnapshot sentMessagesSnapshot = await sentMessagesSnapshotFuture;

        // Collect new contacts
        bool newContactAdded = false;
        for (var doc in sentMessagesSnapshot.docs) {
          List<dynamic> participants = doc['participants'];
          String? otherUserEmail = participants.firstWhere(
            (email) => email != currentUser!.email,
            orElse: () => null,
          );

          if (otherUserEmail != null && !contactList.contains(otherUserEmail)) {
            contactList.add(otherUserEmail);
            newContactAdded = true;
            print("Added new contact: $otherUserEmail"); 
          }
        }

        if (newContactAdded) {
          await _firestore.collection('users').doc(currentUser!.uid).update({
            'contacts': contactList,
          });
        }

        // Fetch additional details for each contact in parallel
        List<Future<Map<String, dynamic>>> contactFutures = contactList.map((contact) async {
          String chatId = _getChatId(currentUser!.email!, contact);

          // Fetch the last message timestamp
          var lastMessageFuture = _firestore
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .limit(1)
              .get();

          // Fetch the locked message count
          var lockedMessagesFuture = _firestore
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .where('isLocked2', isEqualTo: true)
              .where('lockedBy', isEqualTo: currentUser!.uid)
              .get();

          var lastMessageSnapshot = await lastMessageFuture;
          var lockedMessagesSnapshot = await lockedMessagesFuture;

          Timestamp? lastMessageTimestamp;
          if (lastMessageSnapshot.docs.isNotEmpty) {
            lastMessageTimestamp = lastMessageSnapshot.docs.first['timestamp'] as Timestamp;
          }

          int lockedMessageCount = lockedMessagesSnapshot.docs.length;

          return {
            'email': contact,
            'lastMessageTimestamp': lastMessageTimestamp,
            'lockedMessageCount': lockedMessageCount,
          };
        }).toList();

        // Fetch all contact details concurrently
        List<Map<String, dynamic>> contactsWithLastMessage = await Future.wait(contactFutures);

        // Sort contacts by last message timestamp (most recent first)
        contactsWithLastMessage.sort((a, b) {
          Timestamp? timestampA = a['lastMessageTimestamp'];
          Timestamp? timestampB = b['lastMessageTimestamp'];

          if (timestampA == null && timestampB == null) return 0;
          if (timestampA == null) return 1;
          if (timestampB == null) return -1;

          return timestampB.compareTo(timestampA);
        });

        // Update the local state with sorted contacts
        setState(() {
          contacts = contactsWithLastMessage;
        });

        setState(() {
          _isLoading = false; // Stop loading
        });
      } else {
        print("User document does not exist.");
      }
    } catch (e) {
      print("Error loading contacts: $e");
    }
  }

  void addContact() async {
    String newContact = _addContactController.text.trim().toLowerCase();  // Convert to lowercase

    // Validate the new contact
    if (newContact.isEmpty || newContact == currentUser!.email?.toLowerCase() || contacts.contains(newContact)) {
      return;
    }

    // Check if the new contact exists in the "users" collection
    DocumentSnapshot newContactDoc = await _firestore.collection('users').doc(newContact).get();

    // If the new contact does not exist, create a new document for them
    if (!newContactDoc.exists) {
      await _firestore.collection('users').doc(newContact).set({
        'email': newContact,
        'contacts': [], // Initialize with an empty contacts list
      });
    }

    // Add the new contact to the current user's contacts
    await _firestore.collection('users').doc(currentUser!.uid).set({
      'email': currentUser!.email?.toLowerCase(),  // Convert to lowercase
      'contacts': FieldValue.arrayUnion([newContact]),
    }, SetOptions(merge: true));

    // Add the current user to the new contact's contacts (reciprocal relationship)
    await _firestore.collection('users').doc(newContact).update({
      'contacts': FieldValue.arrayUnion([currentUser!.email?.toLowerCase()]),  // Convert to lowercase
    });

    setState(() {
      contacts.add({
        'email': newContact,
        'lastMessageTimestamp': null,
        'lockedMessageCount': 0,
      });
    });

    // Clear the input field
    _addContactController.clear();
  }

  void deleteContact(String contact) async {
    await _firestore.collection('users').doc(currentUser!.uid).update({
      'contacts': FieldValue.arrayRemove([contact]),
    });

    setState(() {
      contacts.remove(contact);
      if (selectedContact == contact) selectedContact = null;
    });
  }

  String _getChatId(String user1, String user2) {
    List<String> sortedIds = [user1, user2]..sort();
    return sortedIds.join('_');
  }

  void deleteChat(String contact) async {
    String chatId = _getChatId(currentUser!.email!, contact);
    await _firestore.collection('chats').doc(chatId).delete();

    setState(() {
      selectedContact = null;
    });
  }
  
  Future<void> pickMedia(String type) async {
    File? pickedFile;

    if (type == "image" || type == "video") {
      final ImagePicker picker = ImagePicker();
      XFile? file = type == "image"
          ? await picker.pickImage(source: ImageSource.gallery)
          : await picker.pickVideo(source: ImageSource.gallery);
      if (file != null) pickedFile = File(file.path);
    }

    if (pickedFile != null) {
      setState(() {
        selectedMedia = pickedFile;
        mediaType = type;
      });
    }
  }

  Future<void> takePicture() async {
    final ImagePicker picker = ImagePicker();
    XFile? file = await picker.pickImage(source: ImageSource.camera);

    if (file != null) {
      File pickedFile = File(file.path);
      setState(() {
        selectedMedia = pickedFile;
        mediaType = "image"; // Set the media type to "image"
      });
    }
  }

  Future<void> takeVideo() async {
    final ImagePicker picker = ImagePicker();
    XFile? file = await picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 5)); //current max duration of video
    
    if (file != null) {
      File pickedFile = File(file.path);
      setState(() {
        selectedMedia = pickedFile;
        mediaType = "video"; 
      });
    }
  }

  Future<String?> uploadToImgur(File file) async {
    final url = Uri.parse('https://api.imgur.com/3/image');
    final request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Client-ID f23175c3a065c42';
    request.files.add(await http.MultipartFile.fromPath('image', file.path));

    try {
      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonResponse = jsonDecode(responseData);
        return jsonResponse['data']['link']; // Public URL of the uploaded image
      } else {
        print("Failed to upload to Imgur: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Imgur upload error: $e");
      return null;
    }
  }

  void sendMessage(String content, String type, {bool isLocked1 = false, bool isLocked2 = false, String? lockedFor, DateTime? unlockTime}) async {
    if (selectedContact == null || content.trim().isEmpty) return;

    String chatId = _getChatId(currentUser!.email!, selectedContact!);

    await _firestore.collection('chats').doc(chatId).collection('messages').add({
      'content': content,
      'type': type, 
      'sender': currentUser!.email,
      'recipient': selectedContact,
      'timestamp': FieldValue.serverTimestamp(),
      'isLocked1': isLocked1, 
      'isLocked2': isLocked2, 
      'lockedFor': lockedFor, 
      'unlockTimestamp': unlockTime != null ? Timestamp.fromDate(unlockTime) : null,
    });

    await _firestore.collection('chats').doc(chatId).set({
      'participants': [currentUser!.email, selectedContact],
    }, SetOptions(merge: true));

    _messageController.clear();
  }
  
  bool isUploading = false;
  void sendSelectedMedia() async {
  if (selectedMedia == null) {
    String content = _messageController.text.trim();
    if (content.isNotEmpty) {
      sendMessage(content, "text");
    }
    return;
  }

  setState(() {
    isUploading = true;
  });

  String? publicUrl;

    if (mediaType == "image") {
      print("Uploading image to Imgur...");
      publicUrl = await uploadToImgur(selectedMedia!);
    } else {
      print("Uploading media to Imgur...");
      publicUrl = await uploadToImgur(selectedMedia!);
    }

    setState(() {
      isUploading = false;
    });

    if (publicUrl == null) {
      print("Media upload failed.");
      return;
    }

    print("Media uploaded successfully: $publicUrl");

    bool isLocked1 = true; // Sender's media is locked
    bool isLocked2 = true; // Recipient's media is locked

    // Ask sender for unlock time or immediate viewing
    DateTime? unlockTime = await _pickUnlockDate();
    String messageType = mediaType ?? "image"; 

    sendMessage(publicUrl, messageType,
      isLocked1: isLocked1,
      isLocked2: isLocked2,
      lockedFor: selectedContact,
      unlockTime: unlockTime,
    );

    setState(() {
      selectedMedia = null;
      mediaType = null;
    });
  }

  void _openMediaPickerForUnlock(String lockedMessageId) async {
    // Initialize AudioPlayer for sound effect
    AudioPlayer audioPlayer = AudioPlayer();
    
    // Get chat ID
    String chatId = _getChatId(currentUser!.email!, selectedContact!);

    // Fetch the locked message
    DocumentSnapshot lockedMessage = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(lockedMessageId)
        .get();

    final lockedMessageData = lockedMessage.data() as Map<String, dynamic>?;
    DateTime? unlockTime = lockedMessageData?.containsKey('unlockTimestamp') == true
        ? (lockedMessageData!['unlockTimestamp'] as Timestamp?)?.toDate()
        : null;

    bool timePassed = unlockTime == null || unlockTime.isBefore(DateTime.now());

    if (!timePassed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("You can only unlock this gift after ${DateFormat('yyyy-MM-dd HH:mm').format(unlockTime)}."),
        ),
      );
      return; 
    }

    print("-------------------------------------------unlockTime: $unlockTime");
    print("-------------------------------------------Current time: ${DateTime.now()}");

    // If the unlock time has passed, proceed with the exchange process
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      // Show confirmation dialog before uploading
      bool? confirmExchange = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Confirm Exchange"),
            content: Text("Are you sure you want to exchange this image to unlock the hybrid gift?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text("Yes"),
              ),
            ],
          );
        },
      );

      if (confirmExchange != true) return;

      setState(() {
        isUploading = true;
      });

      String? publicUrl = await uploadToImgur(File(pickedFile.path));

      setState(() {
        isUploading = false;
      });

      if (publicUrl != null) {

        sendMessage(publicUrl, "image");

        // Unlock the media after the exchange
        await _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .doc(lockedMessageId)
            .update({'isLocked2': false});

        print("Media unlocked!");

        // Play the reveal sound effect
        await audioPlayer.play(AssetSource('audio/reveal-sound-effects.mp3'));

        // Show "Media Unlocked" message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Media Unlocked"),
            duration: Duration(seconds: 2), // Adjust the duration as needed
          ),
        );
      }
    }
  }

  Future<DateTime?> _pickUnlockDate() async {

    bool setTime = await _askUserForUnlockPreference();
    if (!setTime) {
      return null; // No unlock time restriction
    }

    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) return null; 

    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime == null) return null;

    // Combine date and time into a single DateTime object
    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<bool> _askUserForUnlockPreference() async {
    return await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Set Unlock Time?"),
          content: const Text("Do you want to set a specific date and time for unlocking?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: const Text("No, view immediately"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Yes, set date & time"),
            ),
          ],
        );
      },
    ) ?? false; 
  }

  Widget _buildMessageBubble(String content, String type, bool isMe, bool isLocked1, bool isLocked2, Timestamp timestamp, String messageId, {Timestamp? unlockTimestamp}) {
    Widget messageWidget;
    String? imageUrl;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool isLockedForCurrentUser = isMe ? isLocked1 : isLocked2;
    DateTime? unlockTime = unlockTimestamp?.toDate();
    DateTime now = DateTime.now();
    bool isUnlockTimePassed = unlockTime == null || now.isAfter(unlockTime);


    Color senderBubbleColor = isDarkMode ? Colors.blue[500]! : Colors.blue[200]!;
    Color receiverBubbleColor = isDarkMode ? Colors.grey[800]! : Colors.grey[300]!;
    
    
    if (type == "text") {
      messageWidget = Text(content, style: TextStyle(fontSize: 16));
    } 
    else if (type == "image") {
      imageUrl = content;

      if (isLockedForCurrentUser && !isMe) {
        if (isUnlockTimePassed) {
          // If the unlock time has passed, allow the recipient to exchange an image
          messageWidget = GestureDetector(
            onTap: () {
              // Trigger the exchange process
              _openMediaPickerForUnlock(messageId);
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.04), BlendMode.dstATop),
                  child: Image.network(
                    imageUrl,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
                Icon(Icons.lock, size: 50, color: Colors.white),
                Positioned(
                  bottom: 10,
                  child: Text(
                    "Locked",
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ],
            ),
          );
        } else {
          // If the unlock time has not passed, show a prompt
          messageWidget = GestureDetector(
            onTap: () {
              // Show a dialog indicating the unlock time
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text("Locked Gift"),
                    content: Text("You can only reveal this gift after ${DateFormat('yyyy-MM-dd HH:mm').format(unlockTime)}."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("OK"),
                      ),
                    ],
                  );
                },
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.04), BlendMode.dstATop),
                  child: Image.network(
                    imageUrl,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
                Icon(Icons.lock, size: 50, color: Colors.white),
              ],
            ),
          );
        }
      } 
      else {
        // If the media is not locked, show the image
        messageWidget = Image.network(
          imageUrl,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
        );
      }
    } 
    else if (type == "video") {
      if (isLockedForCurrentUser && !isMe) {
        if (isUnlockTimePassed) {
          // If the unlock time has passed, allow the recipient to exchange
          messageWidget = GestureDetector(
            onTap: () {
              // Trigger the exchange process
              _openMediaPickerForUnlock(messageId);
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Blurred video thumbnail preview
                ColorFiltered(
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.04), BlendMode.dstATop),
                  child: Container(
                    width: 200,
                    height: 200,
                    color: Colors.grey[800], 
                    child: Icon(Icons.videocam, size: 50, color: Colors.grey[400]),
                  ),
                ),
                
                Icon(Icons.lock, size: 50, color: Colors.white),
                Positioned(
                  bottom: 10,
                  child: Text(
                    "Available after ${DateFormat('yyyy-MM-dd HH:mm').format(unlockTime ?? DateTime.now())}",
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ],
            ),
          );
        } else {
          // If the unlock time has not passed, show locked state
          messageWidget = GestureDetector(
            onTap: () {
              // Show a dialog indicating the unlock time
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text("Locked Video"),
                    content: Text("You can only reveal this video after ${DateFormat('yyyy-MM-dd HH:mm').format(unlockTime)}."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("OK"),
                      ),
                    ],
                  );
                },
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Blurred video thumbnail preview
                ColorFiltered(
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.04), BlendMode.dstATop),
                  child: Container(
                    width: 200,
                    height: 200,
                    color: Colors.grey[800], // Dark background for video placeholder
                    child: Icon(Icons.videocam, size: 50, color: Colors.grey[400]),
                  ),
                ),
                // Lock icon
                Icon(Icons.lock, size: 50, color: Colors.white),
              ],
            ),
          );
        }
      } 
      else {
        // If the video is not locked, show the video player
        messageWidget = VideoMessageBubble(videoUrl: content);
      }
    }
    else {
      messageWidget = Text("Unsupported format");
    }

    String formattedTime = DateFormat('HH:mm').format(timestamp.toDate());

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? senderBubbleColor : receiverBubbleColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            messageWidget,
            SizedBox(height: 4),
            Text(
              formattedTime,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (selectedContact == null) return SizedBox.shrink();

    String chatId = _getChatId(currentUser!.email!, selectedContact!);

    return StreamBuilder(
      stream: _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

        return ListView(
          reverse: true,
          children: snapshot.data!.docs.map((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            bool isMe = data['sender'] == currentUser?.email;

            String messageType = data.containsKey('type') ? data['type'] : 'text';
            String content = data.containsKey('content') ? data['content'] : '';
            
            // Use the two-flag system
            bool isLocked1 = data['isLocked1'] ?? false; // Locked state for User 1
            bool isLocked2 = data['isLocked2'] ?? false; // Locked state for User 2
            
            Timestamp? timestamp = data['timestamp'] as Timestamp? ?? Timestamp.now();
            String messageId = doc.id;

            return _buildMessageBubble(
              content,
              messageType,
              isMe,
              isLocked1,
              isLocked2,
              timestamp,
              messageId,
            );
          }).toList(),
        );
      },
    );
  }

  Future<bool?> _showDeleteConfirmation(BuildContext context, String contact) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Chat"),
        content: Text("Are you sure you want to delete this chat?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              deleteChat(contact);
              Navigator.pop(context, true);
            },
            child: Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void unlockMedia(String messageId) async {
    String chatId = _getChatId(currentUser!.email!, selectedContact!);

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
          'isLocked2': false, // Unlock for recipient
        });

    print("Media unlocked by user.");
  } 

  // Function to validate the email format
  bool isValidEmail(String email) {
    final emailRegExp = RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
    return emailRegExp.hasMatch(email);
  }

  void _showAddContactDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Add Contact"),
          content: TextField(
            controller: _addContactController,
            decoration: InputDecoration(
              hintText: "Enter valid contact email",
              errorText: isValidEmail(_addContactController.text) ? null : 'Invalid email address',
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (isValidEmail(_addContactController.text)) {
                  addContact();
                  Navigator.pop(context);
                }
              },
              child: Text("Add"),
            ),
            TextButton(
              onPressed: () {
                _addContactController.clear();
                Navigator.pop(context);
              },
              child: Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Column(
      children: [
        if (isUploading)
          Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text("Uploading media...", style: TextStyle(color: Colors.grey[700])),
            ],
          ),

        if (selectedMedia != null)
          Stack(
            alignment: Alignment.topRight,
            children: [
              Container(
                margin: EdgeInsets.all(8),
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: mediaType == "image"
                    ? Image.file(selectedMedia!, width: 200)
                    : mediaType == "video"
                        ? Icon(Icons.video_library, size: 50, color: Colors.blue)
                        : Icon(Icons.audiotrack, size: 50, color: Colors.green),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: GestureDetector(
                  onTap: () => setState(() => selectedMedia = null),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),

        Row(
          children: [
            PopupMenuButton<String>(
              icon: Icon(Icons.attach_file, color: Colors.blue),
              onSelected: (value) {
                if (value == "camera_image") {
                  takePicture(); 
                }
                else if (value == "camera_video"){
                  takeVideo(); 
                }
                else {
                  pickMedia(value); 
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: "camera_image", child: Text("📷 Take picture")), 
                PopupMenuItem(value: "camera_video", child: Text("📷 Take video")),
                PopupMenuItem(value: "image", child: Text("📷 Image from gallery")),
                PopupMenuItem(value: "video", child: Text("📹 Video")),
              ],
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: "Type a message...",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send, color: Colors.blue),
              onPressed: sendSelectedMedia,
            ),
          ],
        ),
      ],
    );
  }

  void resetChatState() {
    setState(() {
      contacts = [];
      selectedContact = null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color.fromARGB(255, 176, 146, 227),
        title: Text(selectedContact ?? "Chat App"),
        leading: widget.showBackButton || selectedContact != null
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();  // go to previous page
                  }
                  setState(() {
                    selectedContact = null;  // Clear the selected contact after navigating back
                  });
                },
              )
            : null, 
        automaticallyImplyLeading: widget.showBackButton,
      ),
        body: _isLoading
          ? Center(
              child: CircularProgressIndicator(), 
            )
          : selectedContact == null
              ? contacts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'You have not added any contacts yet.',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add your first contact now!',
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                          SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _showAddContactDialog,
                            child: Text('Add Contact'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            itemCount: contacts.length,
                            itemBuilder: (context, index) {
                              final contact = contacts[index];
                              final email = contact['email'];
                              final lockedMessageCount = contact['lockedMessageCount'];

                              return Column(
                                children: [
                                  Dismissible(
                                    key: Key(email),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      color: Colors.red,
                                      alignment: Alignment.centerRight,
                                      padding: EdgeInsets.only(right: 20),
                                      child: Icon(Icons.delete, color: Colors.white),
                                    ),
                                    confirmDismiss: (direction) =>
                                        _showDeleteConfirmation(context, email),
                                    onDismissed: (direction) => deleteContact(email),
                                    child: ListTile(
                                      title: Text(email),
                                      trailing: lockedMessageCount > 0
                                          ? Container(
                                              padding: EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                lockedMessageCount.toString(),
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12),
                                              ),
                                            )
                                          : null,
                                      onTap: () => setState(() => selectedContact = email),
                                    ),
                                  ),
                                  Divider(
                                    height: 1, // Height of the divider
                                    thickness: 0.5, // Thickness of the divider line
                                    color: Colors.grey[400], // Color of the divider line
                                    indent: 16, // Optional: Add indentation to the left
                                    endIndent: 16, // Optional: Add indentation to the right
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    )
              : Column(
                  children: [
                    Expanded(child: _buildMessageList()),
                    _buildMessageInput(),
                  ],
                ),
      floatingActionButton: selectedContact == null
          ? FloatingActionButton(
              onPressed: _showAddContactDialog,
              tooltip: 'Add Contact',
              child: Icon(Icons.add),
            )
          : null,
    );
  }
}

class ChatScreen extends StatefulWidget {
  final bool showBackButton;

  const ChatScreen({Key? key, this.showBackButton = false}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();

  void resetState() {
    final state = key is GlobalKey ? (key as GlobalKey).currentState : null;
    if (state is _ChatScreenState) {
      state.resetChatState();
    }
  }
}

class LockedMediaPreview extends StatefulWidget {
  final String imageUrl;
  
  const LockedMediaPreview({required this.imageUrl, super.key});

  @override
  _LockedMediaPreviewState createState() => _LockedMediaPreviewState();
}

class _LockedMediaPreviewState extends State<LockedMediaPreview> {
  bool _isUnlocked = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isUnlocked = true;
        });
      },
      child: Stack(
        children: [
          Image.network(
            widget.imageUrl,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
          ),
          if (!_isUnlocked)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: Icon(Icons.lock, color: Colors.white, size: 40),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class VideoMessageBubble extends StatefulWidget {
  final String videoUrl;

  const VideoMessageBubble({required this.videoUrl, super.key});

  @override
  _VideoMessageBubbleState createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends State<VideoMessageBubble> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: _controller.value.isInitialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : Center(child: CircularProgressIndicator()),
          ),
          if (!_isPlaying)
            Icon(Icons.play_arrow, size: 50, color: Colors.white),
        ],
      ),
    );
  }
}