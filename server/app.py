from flask import Flask, request, jsonify
from flask_cors import CORS
import tensorflow as tf
import numpy as np
import pickle
import mediapipe as mp
import cv2
from PIL import Image
import math
import base64
import io 
import os 


model_path = 'model/gesture_model_json.h5'
label_encoder_path = 'model/label_encoder.pkl'
imageSize = 200 


loaded_model = None
loaded_label_encoder = None
hands_detector = None

mp_hands = mp.solutions.hands


app = Flask(__name__)

CORS(app)


@app.before_request
def load_resources():
    """Tải mô hình, label encoder và khởi tạo MediaPipe Hand."""
  
    global loaded_model, loaded_label_encoder, hands_detector, mp_hands

    # Chỉ tải nếu chưa được tải
    if loaded_model is None or loaded_label_encoder is None or hands_detector is None:
        print(">>> Debug: Đang tải mô hình và các tài nguyên...") 
        try:
          
            if not os.path.exists(model_path):
                raise FileNotFoundError(f"Không tìm thấy file mô hình tại: {model_path}")
            if not os.path.exists(label_encoder_path):
                raise FileNotFoundError(f"Không tìm thấy file label encoder tại: {label_encoder_path}")

            print(f">>> Debug: Đang tải mô hình từ {model_path}")
    
            loaded_model = tf.keras.models.load_model(model_path, compile=False)
            print(">>> Debug: Mô hình TensorFlow đã tải.") 

 
            print(f">>> Debug: Đang tải label encoder từ {label_encoder_path}") 
            with open(label_encoder_path, 'rb') as le_file:
           
                loaded_label_encoder = pickle.load(le_file)
            print(">>> Debug: Label encoder đã tải.") 


            print(">>> Debug: Đang khởi tạo MediaPipe Hands")
  
            hands_detector = mp_hands.Hands(
                static_image_mode=True, 
                max_num_hands=1,      
                min_detection_confidence=0.1 
            )
            print(">>> Debug: MediaPipe Hands đã khởi tạo.") 


            print(">>> Debug: Tất cả tài nguyên đã tải thành công. Kết thúc load_resources()") 


        except FileNotFoundError as fnf_error:
            print(f">>> Lỗi File Not Found: {fnf_error}")
            print("Vui lòng kiểm tra lại đường dẫn tới mô hình và label encoder.")
        
            loaded_model = loaded_label_encoder = hands_detector = None
        except Exception as e:
            print(f">>> Lỗi khi tải tài nguyên: {e}")
            import traceback
            traceback.print_exc()
     
            loaded_model = loaded_label_encoder = hands_detector = None


def calculate_physical_size(image, hand_landmarks):
    """
    Tính toán kích thước vật lý của bàn tay trong ảnh và bounding box.
    Được điều chỉnh để làm việc với ảnh dạng NumPy array.
    """

    img_height, img_width = image.shape[:2]


    x_min, y_min = float('inf'), float('inf')
    x_max, y_max = float('-inf'), float('-inf')

    for landmark in hand_landmarks.landmark:
      
        x, y = int(landmark.x * img_width), int(landmark.y * img_height)
        x_min = min(x_min, x)
        y_min = min(y_min, y)
        x_max = max(x_max, x)
        y_max = max(y_max, y)

 
    try:
        index_mcp = hand_landmarks.landmark[mp_hands.HandLandmark.INDEX_FINGER_MCP]
        pinky_mcp = hand_landmarks.landmark[mp_hands.HandLandmark.PINKY_MCP]

        index_x, index_y = int(index_mcp.x * img_width), int(index_mcp.y * img_height)
        pinky_x, pinky_y = int(pinky_mcp.x * img_width), int(pinky_mcp.y * img_height)

     
        pixel_distance = math.sqrt((index_x - pinky_x)**2 + (index_y - pinky_y)**2)

        if pixel_distance < 1.0:
     
            hand_width_pixels = x_max - x_min
            cm_per_pixel = 8.4 / hand_width_pixels if hand_width_pixels > 0 else 0.0
        else:
           
            cm_per_pixel = 8.4 / pixel_distance

    except Exception as e:
    
        print(f"Lỗi khi tính toán kích thước vật lý: {e}")
        cm_per_pixel = 0.0 

  
    if x_min > x_max or y_min > y_max:
         print("Warning: Bounding box không hợp lệ.")
      
         return cm_per_pixel, (0, 0, image.shape[1], image.shape[0]) 

    return cm_per_pixel, (x_min, y_min, x_max, y_max)





def extract_landmarks(hand_landmarks, image_width, image_height):
    """
    Trích xuất tọa độ landmark đã chuẩn hóa từ phát hiện tay.
    Trả về danh sách phẳng (flattened list) các tọa độ (x, y, z) cho mỗi landmark.
    """
    landmark_coords = []


    for landmark in hand_landmarks.landmark:
   
        landmark_coords.extend([landmark.x, landmark.y, landmark.z])

    return landmark_coords



def predict_gesture_from_image_data(image_data_bytes):
    """
    Xử lý dữ liệu ảnh dạng bytes, phát hiện tay, trích xuất landmark và dự đoán thủ ngữ.

    Args:
        image_data_bytes: Dữ liệu ảnh dưới dạng bytes.

    Returns:
        Một dictionary chứa kết quả dự đoán (label, confidence)
        hoặc thông báo lỗi/không phát hiện tay.
    """
    global loaded_model, loaded_label_encoder, hands_detector


    if loaded_model is None or loaded_label_encoder is None or hands_detector is None:
         print("Lỗi: Mô hình hoặc tài nguyên khác chưa được tải.")
         return {'error': 'Server chưa sẵn sàng. Vui lòng thử lại sau.'}

    try:
    
   
        np_arr = np.frombuffer(image_data_bytes, np.uint8)
        img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR) 
        if img is None:
             print("Lỗi: Không thể giải mã dữ liệu ảnh.")
             return {'error': 'Không thể giải mã dữ liệu ảnh được gửi.'}

        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB) 
        img_height, img_width = img_rgb.shape[:2]

       
        results = hands_detector.process(img_rgb)

     
        if results.multi_hand_landmarks:
            hand_landmarks = results.multi_hand_landmarks[0]

      
            cm_per_pixel, crop_box = calculate_physical_size(img_rgb, hand_landmarks)

      
            landmark_coords = extract_landmarks(hand_landmarks, img_width, img_height)

          
            processed_landmarks = np.array([landmark_coords], dtype=np.float32) 

  
            if processed_landmarks.shape == (1, 63):
               
                prediction = loaded_model.predict(processed_landmarks)

           
                predicted_class_index = np.argmax(prediction[0])
                confidence = float(prediction[0][predicted_class_index]) 

           
                if loaded_label_encoder is None:
                     print("Lỗi: Label encoder chưa được tải.")
                     return {'error': 'Label encoder chưa sẵn sàng.'}

                predicted_label = loaded_label_encoder.inverse_transform([predicted_class_index])[0]

             
                return {
                    'predicted_label': str(predicted_label), 
                    'confidence': confidence,
           
                }
            else:
                 print(f"Lỗi xử lý: Số lượng landmark không đúng. Nhận shape {processed_landmarks.shape}, mong đợi (1, 63).")
                 return {'error': f'Lỗi xử lý dữ liệu landmark.'}
        else:

            print("Không phát hiện tay trong ảnh.")
            return {'message': 'Không phát hiện tay trong ảnh. Vui lòng thử lại.'}

    except Exception as e:

        print(f"Lỗi chung khi xử lý ảnh và dự đoán: {e}")
        import traceback
        traceback.print_exc()
        return {'error': f'Đã xảy ra lỗi trong quá trình xử lý: {e}'}



@app.route('/predict', methods=['POST'])
def predict_gesture_api():
    """
    Endpoint API để nhận ảnh (Base64 encoded trong JSON) và trả về dự đoán thủ ngữ.
    """
  
    if not request.json or 'image' not in request.json:
        return jsonify({'error': 'Body request không hợp lệ. Mong đợi JSON với key "image".'}), 400

    try:

        base64_image_string = request.json['image']
 
        if "," in base64_image_string:
             base64_image_string = base64_image_string.split(",")[1]

        image_data_bytes = base64.b64decode(base64_image_string)


        results = predict_gesture_from_image_data(image_data_bytes)


        if results and 'error' not in results:

             return jsonify(results), 200
        elif results and 'message' in results:

             return jsonify(results), 200
        else:
        
             return jsonify(results), 500

    except Exception as e:

        print(f"Lỗi API chung: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': f'Đã xảy ra lỗi không mong muốn tại API: {e}'}), 500


@app.route('/')
def index():
    """Endpoint đơn giản để kiểm tra server có phản hồi không."""
    return "API Nhận Diện Thủ Ngữ đang chạy!"


if __name__ == '__main__':

    print("Bắt đầu khởi chạy server Flask...")

    app.run(host='0.0.0.0', port=5000, debug=True) 