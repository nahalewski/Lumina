void main() {
  final url = "https://https://primevip.day:443/get.php?username=258389404&password=046347913&type=m3u_plus&output=hls";
  try {
    final uri = Uri.parse(url);
    print("Scheme: ${uri.scheme}");
    print("Host: ${uri.host}");
    print("Port: ${uri.port}");
    print("Path: ${uri.path}");
  } catch (e) {
    print("Error: $e");
  }
}
