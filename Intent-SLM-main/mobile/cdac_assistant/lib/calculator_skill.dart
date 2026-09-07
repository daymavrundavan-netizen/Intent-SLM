import 'agent_context.dart';

class CalculatorResult {
  final double value;
  final String display;

  const CalculatorResult({required this.value, required this.display});
}

class CalculatorSkill {
  bool canHandle(String input, AgentContext context) {
    final text = _normalize(input);

    if (context.activeSkill == AgentSkill.calculator) {
      if (RegExp(r'\d').hasMatch(text)) {
        return true;
      }

      if (text.contains('that')) {
        return true;
      }
    }

    return text.startsWith('calculate ') ||
        text.startsWith('what is ') ||
        text.startsWith('compute ') ||
        text.startsWith('solve ');
  }

  CalculatorResult? evaluate(String input, AgentContext context) {
    var text = _normalize(input);

    text = text
        .replaceFirst(RegExp(r'^calculate\s+'), '')
        .replaceFirst(RegExp(r'^compute\s+'), '')
        .replaceFirst(RegExp(r'^solve\s+'), '')
        .replaceFirst(RegExp(r'^what\s+is\s+'), '');

    //
    // FOLLOW-UP:
    // "multiply that by 10"
    //
    final previous = context.lastNumber;

    if (previous != null && text.contains('that')) {
      final result = _evaluateFollowUp(text, previous);

      if (result != null) {
        context.rememberNumber(result);

        return CalculatorResult(
          value: result,
          display: AgentContext.formatNumber(result),
        );
      }
    }

    //
    // STANDARD:
    // "2 + 3"
    // "238 times 47"
    //
    final result = _evaluateBinary(text);

    if (result == null) {
      return null;
    }

    context.rememberNumber(result);

    return CalculatorResult(
      value: result,
      display: AgentContext.formatNumber(result),
    );
  }

  double? _evaluateBinary(String input) {
    var text = input;

    final replacements = <String, String>{
      'multiplied by': '*',
      'multiply by': '*',
      'times': '*',
      'plus': '+',
      'minus': '-',
      'divided by': '/',
      'divide by': '/',
      'over': '/',
    };

    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, ' ${entry.value} ');
    }

    text = text.replaceAll(RegExp(r'\s+'), ' ');

    final match = RegExp(
      r'^(-?\d+(?:\.\d+)?)\s*'
      r'([+\-*/x])\s*'
      r'(-?\d+(?:\.\d+)?)$',
    ).firstMatch(text);

    if (match == null) {
      return null;
    }

    final left = double.parse(match.group(1)!);

    final operator = match.group(2)!;

    final right = double.parse(match.group(3)!);

    switch (operator) {
      case '+':
        return left + right;

      case '-':
        return left - right;

      case '*':
      case 'x':
        return left * right;

      case '/':
        if (right == 0) {
          return null;
        }

        return left / right;
    }

    return null;
  }

  double? _evaluateFollowUp(String input, double previous) {
    var match = RegExp(
      r'^(?:multiply|times) that by '
      r'(-?\d+(?:\.\d+)?)$',
    ).firstMatch(input);

    if (match != null) {
      return previous * double.parse(match.group(1)!);
    }

    match = RegExp(
      r'^divide that by '
      r'(-?\d+(?:\.\d+)?)$',
    ).firstMatch(input);

    if (match != null) {
      final value = double.parse(match.group(1)!);

      if (value == 0) {
        return null;
      }

      return previous / value;
    }

    match = RegExp(
      r'^add '
      r'(-?\d+(?:\.\d+)?) '
      r'to that$',
    ).firstMatch(input);

    if (match != null) {
      return previous + double.parse(match.group(1)!);
    }

    match = RegExp(
      r'^subtract '
      r'(-?\d+(?:\.\d+)?) '
      r'from that$',
    ).firstMatch(input);

    if (match != null) {
      return previous - double.parse(match.group(1)!);
    }

    match = RegExp(
      r'^that\s*([+\-*/])\s*'
      r'(-?\d+(?:\.\d+)?)$',
    ).firstMatch(input);

    if (match != null) {
      final value = double.parse(match.group(2)!);

      switch (match.group(1)) {
        case '+':
          return previous + value;

        case '-':
          return previous - value;

        case '*':
          return previous * value;

        case '/':
          if (value == 0) {
            return null;
          }

          return previous / value;
      }
    }

    return null;
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[?,!]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
