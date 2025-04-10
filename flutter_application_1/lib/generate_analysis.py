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
PRECISION_HIST_PATH = os.path.join(BASE_DIR, 'precision_histogram.png')

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

# 4. Calculate Precision@k based on existing interaction data
def calculate_precision_at_k(user_prefs, k=5):
    precision_scores = []
    for user_id, prefs in user_prefs.items():
        top_k = prefs['likes'][:k] + prefs['dislikes'][:max(0, k - len(prefs['likes']))]
        relevant = set(prefs['likes'])
        true_positives = sum(1 for item in top_k if item in relevant)
        precision = true_positives / k if k > 0 else 0
        precision_scores.append(precision)
        logger.debug(f"User {user_id} - Precision@{k}: {precision:.2f}")
    if precision_scores:
        average_precision = sum(precision_scores) / len(precision_scores)
        logger.info(f"Calculated average Precision@{k}: {average_precision:.4f}")
        plt.figure(figsize=(8, 6))
        plt.hist(precision_scores, bins=10, range=(0, 1), edgecolor='black', alpha=0.75)
        plt.title(f"Precision@{k} Distribution Across Users")
        plt.xlabel("Precision@K Score")
        plt.ylabel("Number of Users")
        plt.grid(True)
        plt.tight_layout()
        plt.savefig(PRECISION_HIST_PATH)
        logger.info(f"Precision@{k} histogram saved to {PRECISION_HIST_PATH}")
        return average_precision
    else:
        logger.warning("No users to calculate Precision@K.")
        return 0.0

# Rest of your functions (visualize_connections, export_to_csv) remain similar
# but should use the consistent paths defined above

if __name__ == '__main__':
    try:
        logger.info("Starting monitoring process with enhanced validation...")
        logger.debug(f"User preferences count: {len(user_preferences)}")
        logger.debug(f"Sample user data: {dict(list(user_preferences.items())[:1])}")

        generate_dashboard()
        avg_precision = calculate_precision_at_k(user_preferences, k=5)
        logger.info(f"Final Precision@5 across users: {avg_precision:.4f}")

    except Exception as e:
        logger.error(f"Monitoring failed: {str(e)}", exc_info=True)
