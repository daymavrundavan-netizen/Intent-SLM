enum AgentSkill { none, camera, calculator, browser }

class AgentContext {
  AgentSkill activeSkill = AgentSkill.none;

  String? lastCommand;

  double? lastNumber;

  String? lastResult;

  int turn = 0;

  void observe(String command) {
    lastCommand = command;
    turn++;
  }

  void setSkill(AgentSkill skill) {
    activeSkill = skill;
  }

  void rememberNumber(double value) {
    lastNumber = value;
    lastResult = formatNumber(value);
  }

  void reset() {
    activeSkill = AgentSkill.none;
    lastCommand = null;
    lastNumber = null;
    lastResult = null;
    turn = 0;
  }

  static String formatNumber(double value) {
    if (value.isNaN || value.isInfinite) {
      return value.toString();
    }

    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    String text = value.toStringAsFixed(6);

    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }

    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }

    return text;
  }
}
