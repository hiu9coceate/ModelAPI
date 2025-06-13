import 'dart:io';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // Có thể không cần nếu không dùng các service cụ thể
import 'package:camera/camera.dart';
// Loại bỏ tflite_flutter vì không chạy mô hình cục bộ nữa
// import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:typed_data';
import 'dart:convert'; // Cần cho jsonEncode và jsonDecode
// import 'package:flutter/services.dart' show rootBundle; // Không cần load label map cục bộ nữa
// import 'package:image/image.dart' as img; // Có thể không cần nếu không xử lý ảnh trước khi gửi
import 'package:http/http.dart' as http; // Thêm thư viện http
import 'package:image_picker/image_picker.dart'; // Thêm thư viện image_picker (nếu bạn dùng nó để lấy ảnh)


// Hàm main giữ nguyên để khởi tạo camera và chạy ứng dụng
Future<void> main() async {
  // Ensure that plugin services are initialized so that `availableCameras()`
  // can be called before `runApp()`.
  WidgetsFlutterBinding.ensureInitialized();

  // Retrieve the list of available cameras.
  final cameras = await availableCameras();

  // Get a specific camera from the list.
  final firstCamera = cameras.first;

  runApp(MaterialApp(
    title: 'Nhận Diện Thủ Ngữ', // Tên ứng dụng
    theme: ThemeData(
      primarySwatch: Colors.blue,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    ),
    home: HomeScreen(camera: firstCamera),
  ));
}

// HomeScreen widget (StatefulWidget)
class HomeScreen extends StatefulWidget {
  final CameraDescription camera;

  const HomeScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  String recognizedText = ''; // Biến lưu kết quả, sẽ tích lũy
  bool isProcessing = false;



  // --- Cấu hình API Server ---
  // Địa chỉ API của server Python của bạn
  // RẤT QUAN TRỌNG: Thay thế 'YOUR_SERVER_IP_OR_DOMAIN' bằng IP hoặc tên miền thực tế
  // của máy tính đang chạy server Flask.
  // Ví dụ: 'http://192.168.1.100:5000/predict'
  // Nếu dùng Android emulator: 'http://10.0.2.2:5000/predict'
  // Nếu dùng iOS simulator: 'http://localhost:5000/predict'
  final String apiUrl = 'http://10.0.108.121:5000/predict'; 

  

  // --- Hàm cũ để gửi ảnh lên server và nhận kết quả ---
  Future<String?> processHandGestureWithAPI(File imageFile) async {
    try {
     
       if (mounted) {
          setState(() {
            isProcessing = true;
            recognizedText = (recognizedText.isEmpty ? '' : recognizedText + '\n') + 'Đang gửi ảnh lên server...';
          });
       } else { return null; }


      
      List<int> imageBytes = await imageFile.readAsBytes();
   
      String base64Image = base64Encode(imageBytes);

      final Map<String, String> requestBody = {
        'image': base64Image, 
      };

      // <<< ----- BẮT ĐẦU THÊM CODE XUẤT NỘI DUNG JSON ----- >>>
      // Mã hóa Map thành chuỗi JSON để chuẩn bị gửi
      final String jsonBodyString = jsonEncode(requestBody);

      // In ra độ dài của chuỗi JSON (giúp kiểm tra xem có dữ liệu không)
      print(">>> [LOG JSON - CŨ] Chuỗi JSON sẽ gửi (Độ dài): ${jsonBodyString.length}"); // <<< THÊM DÒNG NÀY

      // In ra một phần đầu của chuỗi Base64 để xem thử (ví dụ: 100 ký tự đầu)
      int previewLength = base64Image.length > 100 ? 100 : base64Image.length;
      print(">>> [LOG JSON - CŨ] Preview Base64: ${base64Image.substring(0, previewLength)}..."); // <<< THÊM DÒNG NÀY
      // <<< ----- KẾT THÚC THÊM CODE XUẤT NỘI DUNG JSON ----- >>>


      print(">>> Đang gửi POST đến (Cũ): $apiUrl"); // Log URL (dòng này có thể bạn đã có hoặc muốn thêm)


      // Gửi request POST đến API server
      final response = await http.post(
        Uri.parse(apiUrl), // Phân tích chuỗi URL
        headers: {
          'Content-Type': 'application/json', // Đặt header là JSON
        },
        // body: jsonEncode(requestBody), // Sử dụng chuỗi đã encode ở trên
        body: jsonBodyString, // Gửi chuỗi JSON đã tạo
      );

      print(">>> Phản hồi API (Cũ): ${response.statusCode}"); // Log status code (dòng này có thể bạn đã có)

      // --- Xử lý phản hồi từ server (Giữ nguyên logic gốc của bạn) ---
      if (response.statusCode == 200) {
         // ... (logic xử lý thành công gốc của bạn) ...
         // Ví dụ:
         final Map<String, dynamic> responseData = jsonDecode(response.body);
         if (responseData.containsKey('predicted_label')) {
             final String predictedLabel = responseData['predicted_label'];
             final double confidence = (responseData['confidence'] as num?)?.toDouble() ?? 0.0;
             return "$predictedLabel (${(confidence * 100).toStringAsFixed(1)}%)";
         } else { /* ... xử lý khác ...*/ }
         return "Xử lý thành công nhưng định dạng lạ."; // Ví dụ

      } else {
         // ... (logic xử lý lỗi gốc của bạn) ...
          print('Lỗi API (cũ): ${response.statusCode} - ${response.body}');
          return "Lỗi Server (cũ): Status Code ${response.statusCode}";
      }
    } catch (e, s) { // Giữ nguyên hoặc thêm try-catch cơ bản
      print(">>> Lỗi khi xử lý/gửi ảnh (cũ): $e");
      // print(">>> STACKTRACE (Cũ): $s"); // Bật nếu cần xem chi tiết
      return "Lỗi (cũ): $e";
    } finally {
      // Giữ nguyên logic finally gốc
      if (mounted) {
         setState(() { isProcessing = false; });
      }
    }
  }


  // Hàm chụp ảnh, gọi hàm xử lý với API sau khi chụp
  Future<void> takePicture() async {
    try {
      // Ensure the controller is initialized before taking the picture.
      await _initializeControllerFuture;

      // Không cần đặt isProcessing = true ở đây nữa, đã làm trong processHandGestureWithAPI
      // setState(() {
      //   isProcessing = true;
      //   recognizedText = 'Đang xử lý...';
      // });

      // BẬT ĐÈN FLASH
      await _controller.setFlashMode(FlashMode.auto);


      // Chụp ảnh
      final XFile photo = await _controller.takePicture();
      final File imageFile = File(photo.path); // Lấy file ảnh từ XFile

      // TẮT ĐÈN FLASH sau khi chụp
      await _controller.setFlashMode(FlashMode.off);


      // Gọi hàm xử lý ảnh bằng cách gửi lên API server
      final result = await processHandGestureWithAPI(imageFile);

      // Cập nhật giao diện người dùng với kết quả hoặc thông báo
      // isProcessing đã được đặt false trong processHandGestureWithAPI finally block
      setState(() {
         // Thêm kết quả mới vào cuối chuỗi recognizedText
         if (result != null) {
            recognizedText = (recognizedText.isEmpty ? '' : recognizedText + '\n') + 'Kết quả: ' + result; // Thêm kết quả mới với xuống dòng nếu chuỗi không rỗng
         } else {
            recognizedText = (recognizedText.isEmpty ? '' : recognizedText + '\n') + "Không nhận diện được thủ ngữ."; // Thêm thông báo không nhận diện
         }
      });

    } catch (e) {
      // Nếu có lỗi khi chụp ảnh hoặc xử lý ban đầu
      print('Lỗi khi chụp ảnh: $e');
      setState(() {
        isProcessing = false; // Đảm bảo tắt cờ xử lý
        recognizedText = (recognizedText.isEmpty ? '' : recognizedText + '\n') + "Lỗi chụp ảnh: $e"; // Thêm thông báo lỗi chụp ảnh
      });
    }
  }

  // Hàm xóa kết quả hiển thị
  void clearResults() {
    setState(() {
      recognizedText = ''; // Đặt lại chuỗi kết quả về rỗng
    });
  }

  @override
  void initState() {
    super.initState();

    // Khởi tạo CameraController
    _controller = CameraController(
      widget.camera, // Camera được truyền vào từ main
      ResolutionPreset.medium, // Độ phân giải
      enableAudio: false, // Tắt âm thanh nếu không cần
    );

    // Bắt đầu quá trình khởi tạo controller, trả về Future
    _initializeControllerFuture = _controller.initialize().then((_) {
       // Đặt chế độ flash ban đầu (ví dụ: tắt) sau khi controller được khởi tạo thành công
       _controller.setFlashMode(FlashMode.off);
       // Cập nhật UI nếu cần sau khi camera sẵn sàng (ví dụ: ẩn loading ban đầu)
       setState(() {});
    }).catchError((Object e) {
       // Xử lý lỗi khởi tạo camera
       if (e is CameraException) {
         switch (e.code) {
           case 'CameraAccessDenied':
             print('Lỗi: Quyền truy cập camera bị từ chối.');
             recognizedText = 'Quyền truy cập camera bị từ chối.';
             break;
           default:
             print('Lỗi khởi tạo camera không xác định: ${e.code}');
             recognizedText = 'Lỗi camera: ${e.description ?? e.code}';
             break;
         }
       } else {
          print('Lỗi không xác định khi khởi tạo camera: $e');
          recognizedText = 'Lỗi khởi tạo camera không xác định.';
       }
       setState(() {}); // Cập nhật UI để hiển thị thông báo lỗi
    });

    // --- Các lệnh load model/label map cục bộ không còn cần thiết ---
    // _loadModel();
    // _loadLabelMap();
  }

  @override
  void dispose() {
    // Giải phóng CameraController khi widget bị loại bỏ
    _controller.dispose();
    // --- Giải phóng interpreter TFLite không còn cần thiết ---
    // interpreter?.close();
    super.dispose();
  }

  // --- Xây dựng giao diện người dùng ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận Diện Thủ Ngữ'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Phần hiển thị Camera Preview
          Expanded(
            flex: 3, // Chiếm 3 phần không gian
            child: FutureBuilder<void>(
              future: _initializeControllerFuture, // Chờ Future khởi tạo controller
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                   // Khi Future hoàn thành, kiểm tra controller đã khởi tạo chưa
                   if (_controller.value.isInitialized) {
                     return CameraPreview(_controller); // Hiển thị Camera Preview
                   } else {
                     // Hiển thị lỗi nếu camera không khởi tạo được
                     return Center(
                         child: Text(recognizedText.isNotEmpty ? recognizedText : 'Đang khởi tạo camera...', // Hiển thị lỗi khởi tạo camera
                                     textAlign: TextAlign.center,
                                     style: TextStyle(color: Colors.red, fontSize: 18)));
                   }
                } else {
                  // Trong khi Future đang chạy, hiển thị loading indicator
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          ),

          // Nút Chụp
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: ElevatedButton(
              // Vô hiệu hóa nút khi đang xử lý hoặc camera chưa sẵn sàng
              onPressed: isProcessing || !_controller.value.isInitialized ? null : takePicture,
              child: isProcessing
                  ? const CircularProgressIndicator(color: Colors.white) // Hiển thị loading khi đang xử lý
                  : const Text('Chụp'),
            ),
          ),

          // Phần hiển thị kết quả
          Expanded(
            flex: 2, // Chiếm 2 phần không gian
            child: Container(
              padding: const EdgeInsets.all(10.0),
              width: double.infinity, // Chiếm toàn bộ chiều rộng
              color: Colors.grey[200], // Màu nền xám nhạt
              child: SingleChildScrollView( // Cho phép cuộn nếu nội dung dài
                child: Text(
                  recognizedText.isEmpty
                      ? 'Chụp ảnh để nhận diện thủ ngữ' // Text hướng dẫn khi chưa có kết quả
                      : 'Kết quả:\n' + recognizedText, // Hiển thị kết quả, thêm "Kết quả:\n"
                  style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

           // Nút Xóa kết quả
           Padding(
             padding: const EdgeInsets.symmetric(vertical: 10.0),
             child: ElevatedButton(
               // Chỉ cho phép ấn khi có kết quả để xóa và không đang xử lý
               onPressed: recognizedText.isNotEmpty && !isProcessing ? clearResults : null,
               child: const Text('Xóa kết quả'),
             ),
           ),
        ],
      ),
    );
  }
}