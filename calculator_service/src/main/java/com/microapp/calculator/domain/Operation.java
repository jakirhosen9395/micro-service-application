package com.microapp.calculator.domain;

import java.util.List;

public enum Operation {
    ADD("Addition", "Two or more operands", 2, -1),
    SUBTRACT("Subtraction", "Two or more operands", 2, -1),
    MULTIPLY("Multiplication", "Two or more operands", 2, -1),
    DIVIDE("Division", "Exactly two operands", 2, 2),
    MODULO("Modulo", "Exactly two operands", 2, 2),
    POWER("Power", "Exactly two operands", 2, 2),
    SQRT("Square root", "Exactly one operand", 1, 1),
    PERCENTAGE("Percentage", "Two operands: percentage, value", 2, 2),
    SIN("Sine in degrees", "Exactly one operand", 1, 1),
    COS("Cosine in degrees", "Exactly one operand", 1, 1),
    TAN("Tangent in degrees", "Exactly one operand", 1, 1),
    LOG("Base-10 logarithm", "Exactly one positive operand", 1, 1),
    LN("Natural logarithm", "Exactly one positive operand", 1, 1),
    ABS("Absolute value", "Exactly one operand", 1, 1),
    ROUND("Round half up", "Exactly one operand", 1, 1),
    FLOOR("Floor", "Exactly one operand", 1, 1),
    CEIL("Ceiling", "Exactly one operand", 1, 1),
    FACTORIAL("Factorial", "Exactly one non-negative integer operand", 1, 1);

    private final String description;
    private final String arityDescription;
    private final int minOperands;
    private final int maxOperands;

    Operation(String description, String arityDescription, int minOperands, int maxOperands) {
        this.description = description;
        this.arityDescription = arityDescription;
        this.minOperands = minOperands;
        this.maxOperands = maxOperands;
    }

    public String description() { return description; }
    public String arityDescription() { return arityDescription; }
    public int minOperands() { return minOperands; }
    public int maxOperands() { return maxOperands; }

    public static List<String> names() {
        return java.util.Arrays.stream(values()).map(Enum::name).toList();
    }
}
