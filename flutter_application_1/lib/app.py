from flask import Flask, request, jsonify
import pandas as pd
import numpy as np
import ast
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity, pairwise_distances
from sklearn.decomposition import TruncatedSVD
import logging
from collections import deque, defaultdict
import random
from sklearn.metrics.pairwise import cosine_similarity
from flask_cors import CORS
from collections import defaultdict, deque
import requests
import re
from datetime import datetime, timedelta
import heapq
from sklearn.preprocessing import MinMaxScaler
import os
import csv
from sklearn.naive_bayes import MultinomialNB
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.pipeline import make_pipeline
from sklearn.linear_model import PassiveAggressiveClassifier
from scipy.sparse import csr_matrix

app = Flask(__name__)
CORS(app)
user_preferences = {}

# Configure logging
logging.basicConfig(level=logging.DEBUG)

def load_user_preferences():
    """Load preferences from CSV at startup"""
    try:
        with open('interactions_log.csv', 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                user_id = row['user_id']
                if user_id not in user_preferences:
                    user_preferences[user_id] = {'likes': [], 'dislikes': []}
                
                if row['interaction_type'] == 'like':
                    user_preferences[user_id]['likes'].append(row['product_id'])
                else:
                    user_preferences[user_id]['dislikes'].append(row['product_id'])
    except FileNotFoundError:
        pass  # First run, file doesn't exist yet
load_user_preferences()

def generate_embeddings():
    """Generate and save embeddings if they don't exist"""
    global amazon_df
    logging.info("Generating embeddings...")
    
    # Process in smaller chunks to avoid memory issues
    chunk_size = 100
    embeddings = []
    for i in range(0, len(amazon_df), chunk_size):
        chunk = amazon_df.iloc[i:i+chunk_size]
        texts = chunk.apply(
            lambda row: f"{row['title']} {row.get('features', '')} {row.get('department', '')}", 
            axis=1
        ).tolist()
        embeddings.extend(model.encode(texts))
    
    amazon_df['embedding'] = embeddings
    amazon_df.to_csv(embedding_path, index=False)
    logging.info(f"Saved embeddings to {embedding_path}")

# Load datasets
try:
    df = pd.read_csv("C:\\Users\\leeye\\A_LYY\\1_FYP\\lucky\\flutter_application_1\\lib\\dataset.csv")
    
    # Try loading pre-embedded file first
    embedding_path = "C:\\Users\\leeye\\A_LYY\\1_FYP\\lucky\\flutter_application_1\\lib\\amazon_with_embeddings.csv"
    if os.path.exists(embedding_path):
        amazon_df = pd.read_csv(embedding_path)
        # Convert string representation of embeddings back to arrays
        amazon_df['embedding'] = amazon_df['embedding'].apply(
            lambda x: np.fromstring(x.strip("[]"), sep=" ") if isinstance(x, str) else x
        )
        logging.info("Loaded pre-computed embeddings")
    else:
        amazon_df = pd.read_csv("C:\\Users\\leeye\\A_LYY\\1_FYP\\lucky\\flutter_application_1\\lib\\Amazon products global dataset.csv")
        # Initialize the SentenceTransformer model if not already initialized
        if 'model' not in globals():
            model = SentenceTransformer('all-MiniLM-L6-v2')
            logging.info("SentenceTransformer model initialized.")

        if model is not None:
            generate_embeddings()  # Your embedding generation function
except Exception as e:
    logging.error(f"Data loading failed: {e}")
    df = pd.DataFrame()
    amazon_df = pd.DataFrame()

# Load the SentenceTransformer model
try:
    model = SentenceTransformer('all-MiniLM-L6-v2')
    logging.info("SentenceTransformer model loaded successfully.")
    
    # Generate embeddings if they don't exist
    if not amazon_df.empty and model is not None:
        if 'embedding' not in amazon_df.columns:
            logging.info("Generating product embeddings (this may take several minutes)...")
            
            # Create embeddings using title + features + department
            def generate_embedding(row):
                features = " ".join(row['features']) if isinstance(row.get('features'), list) else ""
                text = f"{row['title']} {features} {row.get('department', '')}"
                return model.encode(text)
            
            # Process in chunks to avoid memory issues
            chunk_size = 500
            embeddings = []
            for i in range(0, len(amazon_df), chunk_size):
                chunk = amazon_df.iloc[i:i+chunk_size]
                embeddings.extend(chunk.apply(generate_embedding, axis=1))
            
            amazon_df['embedding'] = embeddings
            
            # Save embeddings for future use
            embedding_path = "C:\\Users\\leeye\\A_LYY\\1_FYP\\lucky\\flutter_application_1\\lib\\amazon_with_embeddings.csv"
            amazon_df.to_csv(embedding_path, index=False)
            logging.info(f"Embeddings generated and saved to {embedding_path}")
        else:
            logging.info("Embeddings already exist in the dataset")
            
        # Verify embeddings
        if 'embedding' in amazon_df.columns:
            logging.info(f"Embedding check: First embedding length = {len(amazon_df.iloc[0]['embedding'])}")
            
except Exception as e:
    logging.error(f"Failed to initialize embeddings: {e}")
    model = None

# mapping between interests and Amazon departments
interest_to_department = {
    "Shopping": ["Clothing, Shoes & Jewelry", "Watches", "Beauty", "Grocery & Gourmet Food", "Electronics"],
    "Kids": ["Toys & Games", "Baby Products", "Clothing, Shoes & Jewelry"],
    "Health": ["Health & Personal Care", "Vitamins, Minerals & Supplements", "Medical Supplies & Equipment"],
    "Sports": ["Sports & Outdoors", "Outdoor Recreation", "Fitness & Exercise Equipment"],
    "Fashion": ["Clothing, Shoes & Jewelry", "Watches", "Beauty"],
    "Technology": ["Electronics", "Computers", "Wearable Technology", "Headphones, Earphones & Accessories", "Cell Phones & Accessories"],
    "Movies": ["Electronics", "Video Games"],
    "Food": ["Grocery & Gourmet Food", "Drinks", "Fresh & Chilled"],
    "Art": ["Arts, Crafts & Sewing", "Musical Instruments, Stage & Studio"],
    "Travel": ["Outdoor Recreation", "Travel Accessories", "Luggage"],
    "Music": ["Musical Instruments, Stage & Studio", "Headphones, Earphones & Accessories"],
    "Entertainment": ["Video Games", "Electronics", "Toys & Games"]
}
#for helpful? if user input helpful = like product 
@app.route('/like_product', methods=['POST'])
def like_product():
    try:
        data = request.json
        user_id = data['user_id']
        product_id = data['product_id']
        
        # PROPER way to track interaction - pass a dictionary
        track_interaction({
            'user_id': user_id,
            'product_id': product_id, 
            'interaction_type': 'like',
            'timestamp': datetime.now().isoformat()
        })
        
        # Get product info
        product = amazon_df[amazon_df['asin'] == product_id].iloc[0]
        features = " ".join(product.get('features', []))
        text = f"{product['title']} {features} {product.get('department', '')}"
        
        # Learn from positive feedback
        preference_model.learn_from_feedback(text, liked=True)
        
        # Update user preferences
        if user_id not in user_preferences:
            user_preferences[user_id] = {'likes': [], 'dislikes': []}
        user_preferences[user_id]['likes'].append(product_id)
        
        # SUCCESS response with all details
        return jsonify({
            "status": "success",
            "message": "Product liked successfully!",
            "recommendations": preference_model.predict_preference(user_id)[:3],
            "user_stats": {
                "total_likes": len(user_preferences[user_id]['likes']),
                "total_dislikes": len(user_preferences[user_id]['dislikes'])
            },
            "product": {
                "id": product_id,
                "title": product['title'],
                "department": product.get('department', '')
            },
            "model_status": {
                "is_trained": preference_model.is_trained,
                "last_updated": datetime.now().isoformat()
            }
        })
        
    except Exception as e:
        logging.error(f"Error in like_product: {str(e)}", exc_info=True)
        return jsonify({
            "status": "partial_success",
            "message": "Feedback recorded but some processing failed",
            "error": str(e)
        }), 207  # Using 207 Multi-Status to indicate partial success

# Not helpful 
@app.route('/dislike_product', methods=['POST'])
def dislike_product():
    """Endpoint to handle product dislikes"""
    try:
        data = request.json
        user_id = data['user_id']
        product_id = data['product_id']
        
        # Track the interaction
        track_interaction({
            'user_id': user_id,
            'product_id': product_id,
            'interaction_type': 'dislike',
            'timestamp': datetime.now().isoformat()
        })
        
        # Get product info
        product = amazon_df[amazon_df['asin'] == product_id].iloc[0]
        features = " ".join(product.get('features', []))
        text = f"{product['title']} {features} {product.get('department', '')}"
        
        # Learn from this negative feedback
        preference_model.learn_from_feedback(text, liked=False)
        
        # Store in user preferences
        if user_id not in user_preferences:
            user_preferences[user_id] = {'likes': [], 'dislikes': []}
        user_preferences[user_id]['dislikes'].append(product_id)
        
        return jsonify({
            "status": "success",
            "message": "Dislike recorded",
            "model_status": {
                "is_trained": preference_model.is_trained,
                "vocab_size": len(getattr(preference_model.model.steps[0][1], 'vocabulary_', {}))
            }
        })
        
    except Exception as e:
        logging.error(f"Error in /dislike_product: {str(e)}")
        return jsonify({
            "status": "success",  # Still success to user
            "message": "Feedback recorded (learning pending)",
            "error": str(e)
        })  

def build_interaction_matrix():
    """Convert user interactions to a sparse matrix"""
    
    
    all_users = list(user_interactions.keys())
    all_items = list(item_popularity.keys())
    
    user_idx = {u: i for i, u in enumerate(all_users)}
    item_idx = {p: i for i, p in enumerate(all_items)}
    
    # Build sparse matrix
    rows, cols, data = [], [], []
    for user, items in user_interactions.items():
        for item, score in items.items():
            rows.append(user_idx[user])
            cols.append(item_idx[item])
            data.append(score)
    
    return csr_matrix((data, (rows, cols))), user_idx, item_idx

def collaborative_recommendations(user_id, top_n=10):
    """Generate recommendations using collaborative filtering"""
    # Build the interaction matrix
    inter_matrix, user_idx, item_idx = build_interaction_matrix()
    
    # Compute item-item similarities
    item_sim = cosine_similarity(inter_matrix.T)
    
    # Get user's liked items
    user_likes = user_interactions.get(user_id, {})
    
    # Generate recommendations
    rec_scores = defaultdict(float)
    for liked_item, score in user_likes.items():
        if liked_item in item_idx:
            item_index = item_idx[liked_item]
            for other_index, sim_score in enumerate(item_sim[item_index]):
                other_item = list(item_idx.keys())[other_index]  # Simplified lookup
                rec_scores[other_item] += sim_score * score
    
    # Boost items the user has explicitly liked
    if user_id in user_preferences:
        for liked_item in user_preferences[user_id]['likes']:
            rec_scores[liked_item] += 3.0  # Strong boost
            
        # Penalize disliked items
        for disliked_item in user_preferences[user_id]['dislikes']:
            rec_scores[disliked_item] -= 2.0  # Strong penalty
    
    return heapq.nlargest(top_n, rec_scores.items(), key=lambda x: x[1])
    
@app.route('/recommend', methods=['POST'])
def recommend():
    try:
        data = request.json
        logging.info(f"Received request data: {data}")

        if not data:
            return jsonify({"error": "No data provided"}), 400

        # Extract and validate parameters (existing filter logic)
        occasion = data.get("occasion")
        gender = data.get("gender")
        age_range = data.get("age_range")
        price_range = data.get("price_range")
        limit = data.get("limit", 15)
        recent_departments = data.get("recent_departments", [])
        exploration_rate = data.get("exploration_rate", 0.3)

        def matches_gender(product, gender_filter):
            if not gender_filter:
                return True

            title = product.get('title', '').lower()
            description = product.get('description', '').lower()

            # Define gender-specific keywords
            men_keywords = ['men', 'male', 'boy', "men's", "boy's"]
            women_keywords = ['women', 'female', 'girl', "women's", "girl's"]

            if gender_filter.lower() == 'women':
                if any(word in title or word in description for word in men_keywords):
                    return False
                if any(word in title or word in description for word in women_keywords):
                    return True
            elif gender_filter.lower() == 'men':
                if any(word in title or word in description for word in women_keywords):
                    return False
                if any(word in title or word in description for word in men_keywords):
                    return True

            return True


        def filter_products(products, filters):
            filtered = []
            for product in products:
                # Price filter
                if filters.get('price_range'):
                    min_price, max_price = map(float, filters['price_range'].split('-'))
                    if not (min_price <= product.get('price', 0) <= max_price):
                        continue
                
                # Gender filter
                if not matches_gender(product, filters.get('gender')):
                    continue
                
                # Age filter
                if filters.get('age_range'):
                    age_group = filters['age_range']
                    product_age = product.get('age_group', 'all')
                    if age_group != product_age and product_age != 'all':
                        continue
                
                filtered.append(product)
            return filtered

        # Define fallback levels with strictness decreasing
        fallback_levels = [
            {"occasion": occasion, "gender": gender, "age_range": age_range, "price_range": price_range},
            {"occasion": None, "gender": gender, "age_range": age_range, "price_range": price_range},
            {"occasion": None, "gender": None, "age_range": age_range, "price_range": price_range},
            {"occasion": None, "gender": None, "age_range": None, "price_range": price_range},
            {"occasion": None, "gender": None, "age_range": None, "price_range": None},
        ]
        
        recommendations = []
        for level in fallback_levels:
            logging.info(f"Trying fallback level: {level}")
            
            # Get existing recommendations ()
            base_recommendations = fetch_personalized_recommendations(
                {**data, **level}, 
                recent_departments
            )
            
            # Apply strict filtering (existing)
            filtered = filter_products(base_recommendations, level)
            
            if filtered:
                
                if exploration_rate > 0:
                    exploration_count = int(limit * exploration_rate)
                    random_recs = fetch_random_recommendations(exploration_count)
                    random_filtered = filter_products(random_recs, level)
                    recommendations = combine_recommendations(filtered, random_filtered, exploration_rate)
                else:
                    recommendations = filtered
                
                return jsonify({
                    "recommendations": recommendations[:limit],
                    "filter_strictness": level
                })

        # Fallback to trending with strict filtering
        trending = fetch_random_recommendations(limit*2)  # Get more to filter down
        filtered_trending = filter_products(trending, {
            "gender": gender,
            "age_range": age_range,
            "price_range": price_range
        })
        return jsonify({
            "recommendations": filtered_trending[:limit],
            "fallback": True
        })

    except Exception as e:
        logging.error(f"Error in /recommend endpoint: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500
    
@app.route('/recommend_random_products', methods=['GET'])
def recommend_random_products():
    try:
        # Ensure the Amazon dataset is loaded
        if amazon_df.empty:
            logging.error("Amazon dataset is empty or not loaded.")
            return jsonify({"error": "Amazon dataset not available"}), 500

        category_dict = defaultdict(list)

        # Group products by category
        for _, row in amazon_df.iterrows():
            try:
                # Handle invalid or missing price values
                price_val = row.get("initial_price")
                if pd.isna(price_val):
                    price = 0.0
                elif isinstance(price_val, str):
                    if price_val.strip() == "" or price_val.lower() == "null":
                        price = 0.0
                    else:
                        # Remove any non-numeric characters (e.g., currency symbols, quotes)
                        price_str = ''.join(filter(lambda x: x.isdigit() or x == '.', price_val))
                        price = float(price_str)
                else:  # It's already a number (float/int)
                    price = float(price_val)
            except (ValueError, TypeError) as e:
                logging.warning(f"Invalid price value: {row.get('initial_price')}. Defaulting to 0.0. Error: {e}")
                price = 0.0

            price_range = get_price_range(price)

            try:
                # Handle invalid or missing rating values
                rating_val = row.get("rating")
                if pd.isna(rating_val):
                    rating = 0.0
                elif isinstance(rating_val, str):
                    if rating_val.strip() == "" or rating_val.lower() == "null":
                        rating = 0.0
                    else:
                        # Remove any non-numeric characters (e.g., quotes, text)
                        rating_str = ''.join(filter(lambda x: x.isdigit() or x == '.', rating_val))
                        rating = float(rating_str)
                else:  # It's already a number (float/int)
                    rating = float(rating_val)
            except (ValueError, TypeError) as e:
                logging.warning(f"Invalid rating value: {row.get('rating')}. Defaulting to 0.0. Error: {e}")
                rating = 0.0

            category = row.get("department", "Unknown Category")  # Use "department" as category
            product = {
                "Product Name": row.get("title", "Unknown Product"),
                "department": category,
                "images": row.get("images", ""),
                "url": row.get("url", ""),
                "price": price_range,
                "Rating": rating,
            }
            category_dict[category].append(product)

        # Select one random product from each category
        recommendations = {
            category: random.choice(items) for category, items in category_dict.items() if items
        }

        # Convert the dictionary values to a list and limit it to 20 products
        recommendations_list = list(recommendations.values())
        limited_recommendations = recommendations_list[:20]  # Limit to 20 products

        return jsonify({"recommend_random_products": limited_recommendations})

    except Exception as e:
        logging.error(f"Error in /recommend_random_products endpoint: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500
    
def fetch_random_recommendations(limit=10):
    try:
        # Fetch random products
        random_products = amazon_df.sample(n=limit)

        # Fetch trending products (e.g., products with the highest popularity)
        trending_products = amazon_df.sort_values(by="reviews_count", ascending=False).head(limit)

        # Combine random and trending products
        recommendations = pd.concat([random_products, trending_products]).drop_duplicates(subset=['asin']).head(limit)

        # Prepare the response
        recommendations_list = []
        for _, row in recommendations.iterrows():
            # Convert features to a string if it's a list
            features = row.get("features", [])
            if isinstance(features, list):
                features = " ".join(features)

            recommendations_list.append({
                "Product Name": row.get("title", "Unknown Product"),
                "department": row.get("department", "Unknown Department"),
                "images": row.get("images", ""),
                "url": row.get("url", ""),
                "price": float(row.get("final_price", 0.0)) if pd.notna(row.get("final_price")) else 0.0,
                "Rating": float(row.get("rating", 0.0)) if pd.notna(row.get("rating")) else 0.0,
                "Popularity": row.get("reviews_count", 0.0) if pd.notna(row.get("reviews_count")) else 0,
                "features": features,  # Use features as a string
            })

        return recommendations_list
    except Exception as e:
        logging.error(f"Error in fetch_random_recommendations: {e}")
        return []
    
def combine_recommendations(personalized_recommendations, random_recommendations, exploration_rate):
    try:
        # Calculate the number of exploratory items to include
        exploration_count = int(len(personalized_recommendations) * exploration_rate)

        # Combine recommendations
        combined_recommendations = personalized_recommendations + random_recommendations[:exploration_count]

        # Shuffle the combined list to mix personalized and exploratory items
        random.shuffle(combined_recommendations)

        return combined_recommendations

    except Exception as e:
        logging.error(f"Error in combine_recommendations: {e}")
        return personalized_recommendations

def calculate_preference_score(product_row, user_id):
    """Calculate personalized score based on user preferences"""
    try:
        # Base score from popularity/features
        score = product_row.get('reviews_count', 0) / 1000
        
        # Add preference model score if available
        if preference_model.is_trained:
            features = " ".join(product_row.get('features', []))
            text = f"{product_row['title']} {features} {product_row.get('department', '')}"
            score += preference_model.predict_preference(text) * 2
            
        # Boost liked items
        if user_id in user_preferences:
            if product_row['asin'] in user_preferences[user_id]['likes']:
                score += 3
            if product_row['asin'] in user_preferences[user_id]['dislikes']:
                score -= 2
                
        return max(0, score)  # Ensure non-negative
        
    except Exception as e:
        logging.error(f"Error in calculate_preference_score: {e}")
        return 0
    
def fetch_personalized_recommendations(data, recent_departments):
    try:
        occasion = data.get("occasion")
        gender = data.get("gender")
        age_range = data.get("age_range")
        price_range = data.get("price_range")
        limit = data.get("limit", 15)
        offset = data.get("offset", 0)
        bs_category = data.get("bs_category")

        # Filter dataset based on input (optional filters)
        filtered_df = df.copy()

        if occasion:
            if isinstance(occasion, list):  # Handle list of occasions
                filtered_df = filtered_df[filtered_df['Occasion'].isin(occasion)]
            else:
                filtered_df = filtered_df[filtered_df['Occasion'].str.contains(occasion, case=False, na=False)]
        if gender:
            filtered_df = filtered_df[filtered_df['Gender'].str.contains(gender, case=False, na=False)]
        
        # Check if age range is for kids (0-14)
        is_kid = False
        if age_range:
            try:
                if '-' in age_range:
                    start_age, end_age = map(int, age_range.split('-'))
                    if start_age >= 0 and end_age <= 14:
                        is_kid = True
                else:
                    age = int(age_range.replace('+', ''))
                    if age <= 14:
                        is_kid = True
                
                if not is_kid:  # Only apply age filter if not a kid
                    filtered_df = filtered_df[filtered_df['Age'].between(start_age, end_age)]
            except Exception as e:
                logging.error(f"Invalid age range: {age_range}. Error: {e}")
                return []

        if filtered_df.empty and not is_kid:
            logging.warning("No matching products found after filtering.")
            return []

        # If age range is for kids (0-14), override interests with "Kids"
        if is_kid:
            interests = ["Kids"]
            logging.info("Age range 0-14 detected, setting interest to 'Kids'")
        else:
            interests = filtered_df['Interest'].unique().tolist()

        # Map interests to Amazon departments
        departments = []
        for interest in interests:
            departments.extend(interest_to_department.get(interest, []))

        # Remove duplicates in departments
        departments = list(set(departments))

        # Filter Amazon products based on the mapped departments
        recommended_products = amazon_df[amazon_df['department'].isin(departments)]
        unique_recommended_products = recommended_products.drop_duplicates(subset=['asin'])
        
        # Apply personalization based on user preferences if available
        user_id = data.get('user_id')
        if user_id and user_id in user_preferences:
            # Score products based on learned preferences
            unique_recommended_products['preference_score'] = unique_recommended_products.apply(
                lambda row: calculate_preference_score(row, user_id), 
                axis=1
            )
            # Sort by preference score
            unique_recommended_products = unique_recommended_products.sort_values(
                by='preference_score', 
                ascending=False
            )
            
        # Apply price range filtering if price_range is provided
        if price_range:
            logging.info(f"Applying price range filtering: {price_range}")
            try:
                if price_range == "100+":
                    min_price = 100
                    max_price = float('inf')
                else:
                    min_price, max_price = map(float, price_range.split('-'))
                
                unique_recommended_products = unique_recommended_products[
                    (unique_recommended_products['final_price'] >= min_price) &
                    (unique_recommended_products['final_price'] <= max_price)
                ]
            except Exception as e:
                logging.error(f"Invalid price range: {price_range}. Error: {e}")
                return []

        # Apply content-based filtering if recent_departments is provided
        if recent_departments:
            logging.info(f"Applying content-based filtering for departments: {recent_departments}")
            final_recommendations = content_based_filtering(recent_departments, unique_recommended_products, limit)
        else:
            final_recommendations = unique_recommended_products.head(limit)

        # Prepare the response
        recommendations = []
        for _, row in final_recommendations.iterrows():
            recommendations.append({
                "Product Name": row.get("title", "Unknown Product"),
                "department": row.get("department", "Unknown Department"),
                "images": row.get("images", ""),
                "url": row.get("url", ""),
                "price": float(row.get("final_price", 0.0)) if pd.notna(row.get("final_price")) else 0.0,
                "Rating": float(row.get("rating", 0.0)) if pd.notna(row.get("rating")) else 0.0,
                "Popularity": row.get("reviews_count", 0.0) if pd.notna(row.get("reviews_count")) else 0,
                "similarity_score": float(row.get("similarity_score", 0.0)) if "similarity_score" in row else 0.0,
            })

        return recommendations

    except Exception as e:
        logging.error(f"Error in fetch_personalized_recommendations: {e}", exc_info=True)
        return []

def content_based_filtering(recent_departments, amazon_df, limit=15):
    try:
        logging.info(f"Applying content-based filtering for departments: {recent_departments}")

        # Ensure categories are lists
        amazon_df['categories'] = amazon_df['categories'].apply(lambda x: x if isinstance(x, list) else [])

        # Filter products where at least one category matches recent_departments
        filtered_df = amazon_df[
            amazon_df['categories'].apply(lambda cats: any(dep in cats for dep in recent_departments))
        ].copy()  # Use .copy() to avoid SettingWithCopyWarning

        if filtered_df.empty:
            logging.warning("No products matched recent_departments categories.")
            return amazon_df.sample(limit)  # Fallback: return random products

        # Content-Based Filtering (TF-IDF)
        user_query = " ".join(recent_departments)
        vectorizer = TfidfVectorizer(stop_words='english')

        # Fill missing features with empty strings
        filtered_df.loc[:, 'features'] = filtered_df['features'].fillna('')

        # Convert features (lists) to strings
        filtered_df.loc[:, 'features'] = filtered_df['features'].apply(lambda x: " ".join(x) if isinstance(x, list) else x)

        # Fit TF-IDF on features
        tfidf_matrix = vectorizer.fit_transform(filtered_df['features'])

        # Transform user query
        user_query_vector = vectorizer.transform([user_query])
        similarity_scores = cosine_similarity(user_query_vector, tfidf_matrix).flatten()

        # Add similarity scores to the DataFrame
        filtered_df = filtered_df.copy()  # Avoid modifying the original DataFrame
        filtered_df.loc[:, 'similarity_score'] = similarity_scores

        # Sort by similarity and return top products
        recommended_products = filtered_df.sort_values(by='similarity_score', ascending=False).head(limit)
        return recommended_products

    except Exception as e:
        logging.error(f"Error in content_based_filtering: {e}")
        raise

def get_price_range(price):
    if price < 50:
        return "0-50"
    elif 50 <= price < 100:
        return "50-100"
    else:
        return "100+"
    
@app.route('/update_likes', methods=['POST'])
def update_likes():
    try:
        data = request.json
        user_id = data.get('user_id')
        liked_items = data.get('liked_items')
        print(f"Received liked items from user {user_id}: {liked_items}")
        return jsonify({"status": "success"}), 200
    except Exception as e:
        print(f"Error in /update_likes: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/update_saved', methods=['POST'])
def update_saved():
    try:
        data = request.json
        user_id = data.get('user_id')
        saved_items = data.get('saved_items')
        print(f"Received saved items from user {user_id}: {saved_items}")
        return jsonify({"status": "success"}), 200
    except Exception as e:
        print(f"Error in /update_saved: {e}")
        return jsonify({"error": str(e)}), 500

# for More related products
@app.route('/more_related', methods=['POST'])
def more_related():
    try:
        data = request.json
        department = data.get('department')
        bs_category = data.get('bs_category')
        product_name = data.get('product_name')
        user_id = data.get('user_id') 
        semantic_limit = 8  
        collab_limit = 5   
        total_limit = semantic_limit + collab_limit + 6

        if not all([department, bs_category, product_name]):
            return jsonify({"error": "Missing required parameters"}), 400

        amazon_df_clean = amazon_df.copy()

        # --- Strict filtering for bs_category (same department) ---
        filtered_products_strict = amazon_df_clean[
            (amazon_df_clean['department'] == department) & 
            (amazon_df_clean['title'] != product_name)
        ].copy()

        # --- Loose filtering for semantic + collaborative ---
        filtered_products_loose = amazon_df_clean[
            amazon_df_clean['title'] != product_name
        ].copy()

        if filtered_products_loose.empty:
            return jsonify({"error": "No products found"}), 404

        # --- Part 1: Get bs_category matches (strict) ---
        bs_category_products = filtered_products_strict[
            filtered_products_strict['bs_category'] == bs_category
        ].copy()

        bs_category_results = bs_category_products.sample(
            n=min(6, len(bs_category_products)),
            random_state=42
        ) if not bs_category_products.empty else pd.DataFrame()

        # --- Part 2: Get semantic similarity matches (loose) ---
        remaining_products = filtered_products_loose[
            ~filtered_products_loose.index.isin(bs_category_results.index)
        ].copy()

        desc_results = pd.DataFrame()
        if not remaining_products.empty and model is not None:
            try:
                current_product = amazon_df_clean[amazon_df_clean['title'] == product_name].iloc[0]
                current_embedding = current_product.get('embedding')

                if current_embedding is not None:
                    remaining_embeddings = np.stack(
                        remaining_products['embedding'].apply(
                            lambda x: x if x is not None else np.zeros_like(current_embedding)
                        ).values
                    )
                    similarities = cosine_similarity([current_embedding], remaining_embeddings).flatten()
                    
                    remaining_products = remaining_products.assign(similarity=similarities)

                    # Optional weighting based on department match
                    remaining_products['similarity'] *= remaining_products['department'].apply(
                        lambda d: 1.1 if d == department else 1.0
                    )

                    desc_results = remaining_products.nlargest(semantic_limit, 'similarity')
                    desc_results['match_type'] = 'semantic'
            except Exception as e:
                logging.error(f"Error in similarity calculation: {e}")

        if desc_results.empty:
            desc_results = remaining_products.sample(
                n=min(semantic_limit, len(remaining_products)),
                random_state=42
            )
            desc_results['match_type'] = 'random_fallback'

        # --- Part 3: Get collaborative recommendations (loose) ---
        collab_results = pd.DataFrame()
        if user_id:
            try:
                collab_recs = collaborative_recommendations(user_id, top_n=collab_limit)
                if collab_recs:
                    recommended_titles = [rec[0] for rec in collab_recs]
                    collab_results = filtered_products_loose[
                        filtered_products_loose['title'].isin(recommended_titles)
                    ].copy()

                    collab_results['match_type'] = 'collaborative'
                    rec_scores = {rec[0]: rec[1] for rec in collab_recs}
                    collab_results['similarity'] = collab_results['title'].map(rec_scores)

                    collab_results = collab_results[
                        ~collab_results.index.isin(desc_results.index) & 
                        ~collab_results.index.isin(bs_category_results.index)
                    ]
            except Exception as e:
                logging.error(f"Error in collaborative filtering: {e}")

        # --- Combine all results ---
        final_results = pd.concat([bs_category_results, desc_results, collab_results])

        # Fallback to fill up total_limit if needed
        if len(final_results) < total_limit:
            additional_needed = total_limit - len(final_results)
            additional_remaining = filtered_products_loose[
                ~filtered_products_loose.index.isin(final_results.index)
            ].copy()

            if not additional_remaining.empty:
                additional_products = additional_remaining.sample(
                    n=min(additional_needed, len(additional_remaining)), 
                    random_state=42
                )
                additional_products['match_type'] = 'random_fallback'
                final_results = pd.concat([final_results, additional_products])

        final_results = final_results.sample(frac=1, random_state=42).head(total_limit)

        # Prepare JSON response
        products_list = []
        for _, row in final_results.iterrows():
            products_list.append({
                "Product Name": row.get("title", "Unknown"),
                "department": row.get("department", "Unknown"),
                "bs_category": row.get("bs_category", "Unknown"),
                "images": row.get("images", ""),
                "url": row.get("url", ""),
                "price": float(row.get("price", 0)) if pd.notna(row.get("price")) else 0,
                "Rating": float(row.get("rating", 0)) if pd.notna(row.get("rating")) else 0,
                "similarity_score": float(row.get("similarity", 0)) if pd.notna(row.get("similarity")) else 0,
                "match_type": row.get("match_type", "unknown"),
            })

        return jsonify({
            "filtered_products": products_list,
            "stats": {
                "total_products": len(final_results),
                "bs_category_matches": len(bs_category_results),
                "semantic_matches": len(desc_results),
                "collaborative_matches": len(collab_results),
            }
        })

    except Exception as e:
        logging.error(f"Error in more_related: {str(e)}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500

user_click_counts = defaultdict(lambda: defaultdict(int))
  
@app.route('/send-notification', methods=['POST'])
def send_notification():
    try:
        data = request.json
        token = data.get('token')
        title = data.get('title')
        body = data.get('body')

        if not token or not title or not body:
            return jsonify({'error': 'Missing parameters'}), 400

        # FCM server key
        server_key = 'fqp701otSZ-phpTGxB2N5e:APA91bF4u5MYXsqng0RhdsfEqU8DHTu_vz4O4tzD3Kmbgc5qo6c2ev49qmamYSzANU_yofk3t5THH4HMjQBBx6nO7mAlnqaXQi9XceWmwqQd63-GDDh_5Ls'
        url = 'https://fcm.googleapis.com/fcm/send'
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'key={server_key}',
        }
        payload = {
            'to': token,
            'notification': {
                'title': title,
                'body': body,
            },
        }

        print(f"Sending notification to token: {token}")
        print(f"Payload: {payload}")

        response = requests.post(url, headers=headers, json=payload)
        print(f"FCM Response: {response.status_code}, {response.text}")

        if response.status_code == 200:
            return jsonify(response.json()), 200
        else:
            return jsonify({'error': 'Failed to send notification'}), response.status_code

    except Exception as e:
        print(f"Error sending notification: {e}")
        return jsonify({'error': str(e)}), 500

# Enhanced data structures
interaction_log = []  # Define interaction_log as a list to store interaction logs
user_profiles = defaultdict(lambda: {
    'department_affinity': defaultdict(float),
    'click_history': deque(maxlen=100),
    'session_history': [],
    'last_active': None
})

# Add to your existing data structures
user_interactions = defaultdict(dict)  
item_popularity = defaultdict(int)    

def track_interaction(data):
    """Log interactions to CSV for analysis"""
    required_fields = ['user_id', 'product_id', 'interaction_type']
    
    if not all(field in data for field in required_fields):
        logging.error(f"Missing fields in interaction data: {data}")
        return False
    
    try:
        with open('interactions_log.csv', 'a', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=required_fields + ['timestamp'])
            if f.tell() == 0:
                writer.writeheader()
            writer.writerow({
                'user_id': data['user_id'],
                'product_id': data['product_id'],
                'interaction_type': data['interaction_type'],
                'timestamp': data.get('timestamp', datetime.now().isoformat())
            })
        return True
    except Exception as e:
        logging.error(f"Failed to track interaction: {e}")
        return False

def calculate_precision_at_k(user_id, k=5):
    """
    Calculate precision at k for a specific user
    Precision@k = (# of recommended items liked by user) / k
    """
    if user_id not in user_preferences:
        return 0.0
    
    # Get user's liked items
    user_likes = set(user_preferences[user_id]['likes'])
    
    # Get top k recommendations
    try:
        recommendations = preference_model.predict_preference(user_id, k)
        if not recommendations:
            return 0.0
            
        # Count how many recommended items were liked
        hits = sum(1 for item in recommendations if item in user_likes)
        return hits / k
    except Exception as e:
        logging.error(f"Error calculating precision: {e}")
        return 0.0

def calculate_recall_at_k(user_id, k=10):
    """
    Calculate recall at k for a specific user
    Recall@k = (# of recommended items liked by user) / (total # of items user likes)
    """
    if user_id not in user_preferences:
        return 0.0
    
    user_likes = set(user_preferences[user_id]['likes'])
    if not user_likes:
        return 0.0
    
    try:
        recommendations = preference_model.predict_preference(user_id, k)
        if not recommendations:
            return 0.0
            
        hits = sum(1 for item in recommendations if item in user_likes)
        return hits / len(user_likes)
    except Exception as e:
        logging.error(f"Error calculating recall: {e}")
        return 0.0

def calculate_coverage():
    """
    Calculate what percentage of items can be recommended
    Coverage = (# of recommendable items) / (total # of items)
    """
    all_items = set(amazon_df['asin'].unique())
    try:
        # This depends on your model implementation
        recommendable_items = preference_model.get_recommendable_items()
        return len(recommendable_items) / len(all_items) if all_items else 0.0
    except Exception as e:
        logging.error(f"Error calculating coverage: {e}")
        return 0.0

def calculate_diversity(sample_size=100):
    """
    Calculate average pairwise distance between recommended items
    Higher values mean more diverse recommendations
    """
    try:
        # Get sample of recommendations across users
        sample_recommendations = []
        for user in list(user_preferences.keys())[:sample_size]:
            recs = preference_model.predict_preference(user, 5)
            if recs:
                sample_recommendations.extend(recs)
        
        if not sample_recommendations:
            return 0.0
            
        # Get item embeddings or features
        item_features = []
        for item in set(sample_recommendations):
            product = amazon_df[amazon_df['asin'] == item].iloc[0]
            features = " ".join(product.get('features', []))
            text = f"{product['title']} {features} {product.get('department', '')}"
            item_features.append(text)
        
        # Use TF-IDF or your model's feature representation
        tfidf_matrix = preference_model.vectorizer.transform(item_features)
        
        # Calculate pairwise cosine distances
        distances = pairwise_distances(tfidf_matrix, metric='cosine')
        np.fill_diagonal(distances, 0)  # Ignore self-similarity
        
        # Return average distance
        return distances.mean()
    except Exception as e:
        logging.error(f"Error calculating diversity: {e}")
        return 0.0

def get_total_interactions():
    """Count total user interactions tracked"""
    return len(interaction_log) if interaction_log else 0

def get_conversion_rate(window_days=7):
    """
    Calculate recommendation conversion rate
    Conversion Rate = (# likes from recommendations) / (# recommendations shown)
    """
    try:
        recent_interactions = [i for i in interaction_log 
                              if i['timestamp'] > datetime.now() - timedelta(days=window_days)]
        
        recommendations_shown = sum(1 for i in recent_interactions 
                                  if i['interaction_type'] == 'recommendation_shown')
        recommendations_liked = sum(1 for i in recent_interactions 
                                  if i['interaction_type'] == 'like' 
                                  and i.get('source') == 'recommendation')
        
        return recommendations_liked / recommendations_shown if recommendations_shown > 0 else 0.0
    except Exception as e:
        logging.error(f"Error calculating conversion rate: {e}")
        return 0.0

def calculate_like_dislike_ratio():
    """Calculate overall like/dislike ratio"""
    likes = sum(len(u['likes']) for u in user_preferences.values())
    dislikes = sum(len(u['dislikes']) for u in user_preferences.values())
    return likes / (likes + dislikes) if (likes + dislikes) > 0 else 0.0

def find_common_features(preference_type):
    """
    Find most common features among liked/disliked items
    """
    feature_counts = defaultdict(int)
    
    for user_id, prefs in user_preferences.items():
        for product_id in prefs.get(preference_type, []):
            try:
                product = amazon_df[amazon_df['asin'] == product_id].iloc[0]
                for feature in product.get('features', []):
                    feature_counts[feature] += 1
            except:
                continue
    
    return dict(sorted(feature_counts.items(), key=lambda x: x[1], reverse=True)[:5])

@app.route('/model_metrics')
def model_metrics():
    """Comprehensive model evaluation endpoint"""
    try:
        sample_user = next(iter(user_preferences.keys())) if user_preferences else None
        
        metrics = {
            "precision@5": calculate_precision_at_k(sample_user, 5) if sample_user else 0.0,
            "recall@10": calculate_recall_at_k(sample_user, 10) if sample_user else 0.0,
            "coverage": calculate_coverage(),
            "diversity": calculate_diversity(),
            "conversion_rate": get_conversion_rate(),
            "like_dislike_ratio": calculate_like_dislike_ratio(),
            "active_users": len(user_preferences),
            "total_interactions": get_total_interactions(),
            "common_liked_features": find_common_features('likes'),
            "common_disliked_features": find_common_features('dislikes')
        }
        
        return jsonify({
            "status": "success",
            "metrics": metrics,
            "model_status": {
                "is_trained": preference_model.is_trained,
                "last_trained": preference_model.last_trained_time,
                "training_samples": preference_model.training_samples
            }
        })
        
    except Exception as e:
        logging.error(f"Error in model metrics: {e}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route('/user_metrics/<user_id>')
def user_metrics(user_id):
    """User-specific recommendation metrics"""
    try:
        if user_id not in user_preferences:
            return jsonify({
                "status": "success",
                "message": "New user - insufficient data",
                "metrics": None
            })
        
        metrics = {
            "personal_precision@5": calculate_precision_at_k(user_id, 5),
            "personal_recall@10": calculate_recall_at_k(user_id, 10),
            "total_likes": len(user_preferences[user_id]['likes']),
            "total_dislikes": len(user_preferences[user_id]['dislikes']),
            "recommendation_history": [
                i for i in interaction_log 
                if i['user_id'] == user_id 
                and i['interaction_type'] in ('recommendation_shown', 'like', 'dislike')
            ][-10:]  # Last 10 interactions
        }
        
        return jsonify({
            "status": "success",
            "metrics": metrics
        })
        
    except Exception as e:
        logging.error(f"Error in user metrics: {e}")
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
            
class PreferenceModel:
    def __init__(self):
        # Initialize with a simple model that can be updated online
        self.model = make_pipeline(
            TfidfVectorizer(max_features=5000),
            PassiveAggressiveClassifier()
        )
        self.is_trained = False
        self.vectorizer = None
        self.classifier = None
        self.X_train = []
        self.y_train = []
        
    def learn_from_feedback(self, text, liked=True):
        """Update model with new feedback"""
        try:
            # Convert text to string if it's not already
            text = str(text) if not isinstance(text, str) else text
            
            # Add to training data
            self.X_train.append(text)
            self.y_train.append(1 if liked else 0)
            
            # Retrain model periodically (every 10 samples for efficiency)
            if len(self.X_train) % 10 == 0 or not self.is_trained:
                if len(set(self.y_train)) >= 2:  # Need both positive and negative samples
                    self.model.fit(self.X_train, self.y_train)
                    self.is_trained = True
                    logging.info(f"Model retrained with {len(self.X_train)} samples")
            
            return True
        except Exception as e:
            logging.error(f"Error in learn_from_feedback: {e}")
            return False
            
    def predict_preference(self, user_id, k=5):
        """Temporary implementation for testing"""
        if not hasattr(self, 'dummy_items'):
            # Get top popular items as fallback
            self.dummy_items = amazon_df['asin'].value_counts().index[:100].tolist()
        
        # Return random items from dummy pool (replace with real logic)
        return random.sample(self.dummy_items, min(k, len(self.dummy_items)))

def calculate_precision_at_k(user_id, k=5):
    liked = user_preferences.get(user_id, {}).get('likes', [])
    recs = preference_model.predict_preference(user_id, k)
    hits = sum(1 for item in recs if item in liked)
    return hits / k if k > 0 else 0

@app.route('/debug_user/<user_id>')
def debug_user(user_id):
    """See a user's preferences and recommendations"""
    return jsonify({
        'preferences': user_preferences.get(user_id, {}),
        'last_3_interactions': interaction_log[-3:],
        'current_recommendations': preference_model.predict_preference(user_id)[:5],
        'recommendation_reasons': [
            {
                'product_id': item,
                'reason': f"Recommended because {len(preference_model.get_similar_users(user_id))} similar users liked this"
            } 
            for item in preference_model.predict_preference(user_id)[:3]
        ]
    })

#  Initialize the model
preference_model = PreferenceModel()

if __name__ == '__main__':    
    app.run(host="0.0.0.0", port=5000, debug=True)