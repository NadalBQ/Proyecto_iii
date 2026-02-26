import pickle
from sklearn.metrics import accuracy_score

def train_model():
    '''Trains a predictive model for risk based on the data available'''
    pass


def load_model(path):
    '''Loads an already trained model from its `path` (including its name and extension)'''
    M = None
    try:
        with open(path, "rb") as file:
            M = pickle.load(file)
        print("Model loaded successfully.")
    except (OSError, pickle.PickleError) as e:
        print(f"Error loading model: {e}")
    return M

def save_model(M, path):
    '''Saves an already trained model to its `path` (including its name and extension)'''
    try:
        with open(path, "wb") as file:
            # Use highest protocol for efficiency
            pickle.dump(M, file, protocol=pickle.HIGHEST_PROTOCOL)
        print(f"Model saved to '{path}'")
        return True
    except (OSError, pickle.PickleError) as e:
        print(f"Error saving model: {e}")
    return False



def test_model(M, X_test, Y_test):
    '''Tests an already trained model against custom-made test cases to see if it performs well in predicting the real values of risk'''
    Y_pred = M.predict(X_test)
    acc = accuracy_score(Y_test, Y_pred)
    return acc


