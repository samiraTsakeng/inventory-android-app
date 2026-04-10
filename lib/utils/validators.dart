class Validators {
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required please';
    }
    final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegExp.hasMatch(value)) {
      return 'Enter a valid Email address';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'password is required dear';
    }
    if (value.length < 6) {
      return 'password must be at least 6 characters';
    }
    return null;
  }

  static String? validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Name is required';
    }
    if (value.length < 2) {
      return 'Name must be at least 2 characters';
    }
    return null;
  }
  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final phoneRegExp = RegExp(r'^[0-9]{9,15}$');
    if (!phoneRegExp.hasMatch(value.replaceAll(' ', ''))) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? validatePost(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return null;
  }
}