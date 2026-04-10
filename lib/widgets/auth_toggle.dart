import 'package:flutter/material.dart';
import '../utils/constants.dart';

class AuthToggle extends StatelessWidget {
  final bool isTestMode;
  final Function(bool) onToggle;

  const AuthToggle({
    Key? key,
    required this.isTestMode,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !isTestMode ? AppColors.primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  AppStrings.erpMode,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: !isTestMode ? Colors.white : AppColors.textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isTestMode ? AppColors.secondaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  AppStrings.testMode,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isTestMode ? Colors.white : AppColors.textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}