class User {
  final String? id;
  final String? name;
  final String email;
  final String? phone;
  final String? post;
  final bool isTestUser;
  final String? erpUserId;
  final String? token;

  User({
    this.id,
    required this.name,
    required this.email,
    this.phone,
    this.post,
    this.isTestUser = false,
    this.erpUserId,
    this.token,
});

  //For creating test users
    factory User.test({
    required String name,
    required String email,
    String? phone,
    String? post,
}){
      return User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        email: email,
        phone: phone,
        post: post,
        isTestUser: true,
      );
    }

    //convert to JSON for storage
    Map<String, dynamic> toJson() {
      return {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'post': post,
        'isTestUser': isTestUser,
        'erpUserId': erpUserId,
        'token': token,
      };
    }

    //Create from JSON
    factory User.fromJson(Map<String, dynamic> json) {
      return User(
        id: json['id'],
        name: json['name'],
        email: json['email'],
        phone: json['phone'],
        post: json['post'],
        isTestUser: json['isTestUser'] ?? false,
        erpUserId: json['erpUserId'],
        token: json['token'],
      );
    }
}