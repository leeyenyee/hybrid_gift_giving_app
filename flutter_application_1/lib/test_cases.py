import pandas as pd
import matplotlib.pyplot as plt
import networkx as nx
import logging
from collections import defaultdict
import os

# Configure logging with more detailed output
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 1. Define consistent file paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INTERACTIONS_LOG_PATH = os.path.join(BASE_DIR, 'interactions_log.csv')
USER_PREFS_PATH = os.path.join(BASE_DIR, 'user_preferences.csv')
DASHBOARD_PATH = os.path.join(BASE_DIR, 'user_metrics.png')
NETWORK_PATH = os.path.join(BASE_DIR, 'user_item_network.png')

# 2. Enhanced data loading with validation
def load_user_preferences():
    """Load and validate user preferences from interactions log"""
    user_prefs = defaultdict(lambda: {'likes': [], 'dislikes': []})
    
    try:
        if os.path.exists(INTERACTIONS_LOG_PATH):
            logger.debug(f"Loading interactions from {INTERACTIONS_LOG_PATH}")
            interactions = pd.read_csv(INTERACTIONS_LOG_PATH)
            
            # Validate required columns
            required_columns = {'user_id', 'product_id', 'interaction_type', 'timestamp'}
            if not required_columns.issubset(interactions.columns):
                missing = required_columns - set(interactions.columns)
                raise ValueError(f"Missing columns in CSV: {missing}")
            
            # Process interactions
            for _, row in interactions.iterrows():
                if row['interaction_type'] == 'like':
                    user_prefs[row['user_id']]['likes'].append(row['product_id'])
                elif row['interaction_type'] == 'dislike':
                    user_prefs[row['user_id']]['dislikes'].append(row['product_id'])
            
            logger.debug(f"Loaded {len(user_prefs)} users with preferences")
        else:
            logger.warning(f"Interactions log not found at {INTERACTIONS_LOG_PATH}")
            
    except Exception as e:
        logger.error(f"Error loading preferences: {str(e)}")
    
    return user_prefs

# Initialize user_preferences
user_preferences = load_user_preferences()

# 3. Enhanced dashboard generation with data validation
def generate_dashboard(save_path=DASHBOARD_PATH):
    """Generate analytics dashboard with raw interaction visualization"""
    try:
        plt.figure(figsize=(15, 10))
        
        # Load interactions data
        interactions = pd.read_csv(INTERACTIONS_LOG_PATH)
        
        # --- Panel 1: Raw Interactions Timeline ---
        plt.subplot(2, 2, 1)
        if not interactions.empty:
            # Convert timestamp to datetime and sort
            interactions['timestamp'] = pd.to_datetime(interactions['timestamp'])
            interactions = interactions.sort_values('timestamp')
            
            # Plot raw interactions (no year grouping)
            plt.plot(interactions['timestamp'], 
                    range(1, len(interactions)+1),  # Cumulative count
                    marker='o', markersize=2, linestyle='-')
            plt.title(f"All Interactions Timeline\n(Total: {len(interactions)})")
            plt.xlabel("Timestamp")
            plt.ylabel("Interaction Count")
            plt.grid(True)
        else:
            plt.text(0.5, 0.5, 'No interaction data', ha='center')

        # --- Panel 2: Interaction Types Breakdown ---
        plt.subplot(2, 2, 2)
        if not interactions.empty:
            interaction_counts = interactions['interaction_type'].value_counts()
            interaction_counts.plot(kind='pie', autopct='%1.1f%%')
            plt.title("Interaction Types Distribution")
        else:
            plt.text(0.5, 0.5, 'No interaction data', ha='center')

        # --- Panel 3: Top Active Users ---
        plt.subplot(2, 2, 3)
        if not interactions.empty:
            top_users = interactions['user_id'].value_counts().head(10)
            top_users.plot(kind='barh')
            plt.title("Top 10 Active Users")
            plt.xlabel("Interaction Count")
        else:
            plt.text(0.5, 0.5, 'No user data', ha='center')

        # --- Panel 4: Recent Activity Sample ---
        plt.subplot(2, 2, 4)
        if not interactions.empty:
            sample_data = interactions.tail(5)[['timestamp', 'user_id', 'interaction_type']]
            plt.axis('off')
            plt.table(cellText=sample_data.values,
                     colLabels=sample_data.columns,
                     loc='center',
                     cellLoc='center')
            plt.title("Recent Activity Sample", y=1.08)
        else:
            plt.text(0.5, 0.5, 'No recent activity', ha='center')

        plt.tight_layout()
        plt.savefig(save_path, dpi=120)
        logger.info(f"Dashboard saved to {save_path}")

    except Exception as e:
        logger.error(f"Dashboard generation failed: {str(e)}", exc_info=True)

# Rest of your functions (visualize_connections, export_to_csv) remain similar
# but should use the consistent paths defined above

if __name__ == '__main__':
    try:
        logger.info("Starting monitoring process with enhanced validation...")
        
        # Data validation checkpoint
        logger.debug(f"User preferences count: {len(user_preferences)}")
        logger.debug(f"Sample user data: {dict(list(user_preferences.items())[:1])}")
        
        generate_dashboard()
        # visualize_connections()
        # export_to_csv()
        
        logger.info("Monitoring completed with validation")
    except Exception as e:
        logger.error(f"Monitoring failed: {str(e)}", exc_info=True)

# test_cases.py
# import pytest
# from app import app, preference_model, user_preferences, calculate_precision_at_k
# import json

# # Test client setup
# @pytest.fixture
# def client():
#     app.config['TESTING'] = True
#     with app.test_client() as client:
#         yield client

# # Test data
# TEST_USER = "e0aTZkpTnsSsvHpRMIFWm2UguJM2"
# TEST_PRODUCT_LIKE = "B001G8XYFS"
# TEST_PRODUCT_DISLIKE = "B00008JOMD"

# def test_like_product(client):
#     """Test that liking a product works and updates recommendations"""
#     # Initial like
#     response = client.post('/like_product', 
#         json={'user_id': TEST_USER, 'product_id': TEST_PRODUCT_LIKE})
    
#     assert response.status_code == 200
#     data = json.loads(response.data)
    
#     # Check response structure
#     assert data['status'] == "success"
#     assert "recommendations" in data
    
#     # Verify user preferences updated
#     assert TEST_USER in user_preferences
#     assert TEST_PRODUCT_LIKE in user_preferences[TEST_USER]['likes']

# def test_recommendations_after_like(client):
#     """Test recommendations change after liking a product"""
#     # Get initial recommendations
#     initial_recs = preference_model.predict_preference(TEST_USER)
    
#     # Like a product
#     client.post('/like_product', 
#         json={'user_id': TEST_USER, 'product_id': TEST_PRODUCT_LIKE})
    
#     # Get updated recommendations
#     updated_recs = preference_model.predict_preference(TEST_USER)
    
#     # Recommendations should change (at least 1 new item)
#     assert len(set(updated_recs) - set(initial_recs)) > 0

# def test_dislike_filtering(client):
#     """Test disliked products don't appear in recommendations"""
#     # Dislike a product
#     client.post('/dislike_product', 
#         json={'user_id': TEST_USER, 'product_id': TEST_PRODUCT_DISLIKE})
    
#     # Get recommendations
#     recs = preference_model.predict_preference(TEST_USER)
    
#     # Verify disliked item not in recommendations
#     assert TEST_PRODUCT_DISLIKE not in recs

# def test_new_user_recommendations():
#     """Test new users get reasonable default recommendations"""
#     recs = preference_model.predict_preference("brand_new_user")
#     assert len(recs) > 0  # Should get some recommendations
#     assert all(isinstance(item, str) for item in recs)  # All should be product IDs

# def test_precision_calculation():
#     """Test recommendation quality metric"""
#     # Simulate user with 5 liked products
#     user_preferences["metric_test_user"] = {
#         'likes': ['P1', 'P2', 'P3', 'P4', 'P5'],
#         'dislikes': []
#     }
    
#     # Mock recommendations (3/5 are good)
#     preference_model.predict_preference = lambda user_id, k=5: ['P1', 'P3', 'P5', 'P7', 'P9']
    
#     precision = calculate_precision_at_k("metric_test_user", k=5)
#     assert precision == 0.6  # 3/5 correct