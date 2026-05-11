package com.microapp.calculator.domain;

import com.microapp.calculator.exception.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.math.MathContext;
import java.math.RoundingMode;
import java.util.List;
import java.util.Locale;

@Component
public class CalculatorEngine {
    private static final MathContext MC = MathContext.DECIMAL128;
    private static final int SCALE = 18;
    private static final BigDecimal HUNDRED = BigDecimal.valueOf(100);

    public BigDecimal evaluateOperation(String operationName, List<BigDecimal> operands) {
        Operation operation = parseOperation(operationName);
        List<BigDecimal> ops = operands == null ? List.of() : operands;
        return switch (operation) {
            case ADD -> normalize(requireAtLeast(operation, ops, 2).stream().reduce(BigDecimal.ZERO, (a, b) -> a.add(b, MC)));
            case SUBTRACT -> subtract(requireAtLeast(operation, ops, 2));
            case MULTIPLY -> normalize(requireAtLeast(operation, ops, 2).stream().reduce(BigDecimal.ONE, (a, b) -> a.multiply(b, MC)));
            case DIVIDE -> {
                List<BigDecimal> values = requireExactly(operation, ops, 2);
                yield divide(values.get(0), values.get(1));
            }
            case MODULO -> {
                List<BigDecimal> values = requireExactly(operation, ops, 2);
                if (isZero(values.get(1))) {
                    throw bad("CALC_DIVIDE_BY_ZERO", "Modulo by zero is not allowed");
                }
                yield normalize(values.get(0).remainder(values.get(1), MC));
            }
            case POWER -> {
                List<BigDecimal> values = requireExactly(operation, ops, 2);
                yield normalize(BigDecimal.valueOf(Math.pow(values.get(0).doubleValue(), values.get(1).doubleValue())).setScale(SCALE, RoundingMode.HALF_UP));
            }
            case SQRT -> sqrt(requireExactly(operation, ops, 1).get(0));
            case PERCENTAGE -> {
                List<BigDecimal> values = requireExactly(operation, ops, 2);
                yield normalize(values.get(1).multiply(values.get(0), MC).divide(HUNDRED, SCALE, RoundingMode.HALF_UP));
            }
            case SIN -> oneMath(operation, ops, v -> Math.sin(Math.toRadians(v)));
            case COS -> oneMath(operation, ops, v -> Math.cos(Math.toRadians(v)));
            case TAN -> oneMath(operation, ops, v -> Math.tan(Math.toRadians(v)));
            case LOG -> log10(requireExactly(operation, ops, 1).get(0));
            case LN -> ln(requireExactly(operation, ops, 1).get(0));
            case ABS -> normalize(requireExactly(operation, ops, 1).get(0).abs());
            case ROUND -> normalize(requireExactly(operation, ops, 1).get(0).setScale(0, RoundingMode.HALF_UP));
            case FLOOR -> normalize(requireExactly(operation, ops, 1).get(0).setScale(0, RoundingMode.FLOOR));
            case CEIL -> normalize(requireExactly(operation, ops, 1).get(0).setScale(0, RoundingMode.CEILING));
            case FACTORIAL -> factorial(requireExactly(operation, ops, 1).get(0));
        };
    }

    public BigDecimal evaluateExpression(String expression) {
        if (expression == null || expression.isBlank()) {
            throw bad("CALC_INVALID_EXPRESSION", "Expression is required");
        }
        return new Parser(expression).parse();
    }

    private Operation parseOperation(String operationName) {
        if (operationName == null || operationName.isBlank()) {
            throw bad("CALC_OPERATION_REQUIRED", "operation is required for operation mode");
        }
        try {
            return Operation.valueOf(operationName.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException ex) {
            throw bad("CALC_INVALID_OPERATION", "Unsupported operation: " + operationName);
        }
    }

    private BigDecimal subtract(List<BigDecimal> operands) {
        BigDecimal result = operands.get(0);
        for (int i = 1; i < operands.size(); i++) {
            result = result.subtract(operands.get(i), MC);
        }
        return normalize(result);
    }

    private BigDecimal divide(BigDecimal left, BigDecimal right) {
        if (isZero(right)) {
            throw bad("CALC_DIVIDE_BY_ZERO", "Division by zero is not allowed");
        }
        return normalize(left.divide(right, SCALE, RoundingMode.HALF_UP));
    }

    private BigDecimal sqrt(BigDecimal value) {
        if (value.compareTo(BigDecimal.ZERO) < 0) {
            throw bad("CALC_NEGATIVE_SQUARE_ROOT", "Square root of a negative number is not allowed");
        }
        return normalize(BigDecimal.valueOf(Math.sqrt(value.doubleValue())).setScale(SCALE, RoundingMode.HALF_UP));
    }

    private BigDecimal log10(BigDecimal value) {
        if (value.compareTo(BigDecimal.ZERO) <= 0) {
            throw bad("CALC_INVALID_LOGARITHM", "Logarithm input must be greater than zero");
        }
        return normalize(BigDecimal.valueOf(Math.log10(value.doubleValue())).setScale(SCALE, RoundingMode.HALF_UP));
    }

    private BigDecimal ln(BigDecimal value) {
        if (value.compareTo(BigDecimal.ZERO) <= 0) {
            throw bad("CALC_INVALID_LOGARITHM", "Natural logarithm input must be greater than zero");
        }
        return normalize(BigDecimal.valueOf(Math.log(value.doubleValue())).setScale(SCALE, RoundingMode.HALF_UP));
    }

    private BigDecimal factorial(BigDecimal value) {
        try {
            BigInteger integer = value.toBigIntegerExact();
            if (integer.signum() < 0) {
                throw bad("CALC_INVALID_FACTORIAL", "Factorial input must be a non-negative integer");
            }
            if (integer.compareTo(BigInteger.valueOf(1000)) > 0) {
                throw bad("CALC_FACTORIAL_TOO_LARGE", "Factorial input must be less than or equal to 1000");
            }
            BigInteger result = BigInteger.ONE;
            for (BigInteger i = BigInteger.TWO; i.compareTo(integer) <= 0; i = i.add(BigInteger.ONE)) {
                result = result.multiply(i);
            }
            return new BigDecimal(result);
        } catch (ArithmeticException ex) {
            throw bad("CALC_INVALID_FACTORIAL", "Factorial input must be a non-negative integer");
        }
    }

    private BigDecimal oneMath(Operation operation, List<BigDecimal> operands, DoubleFunction function) {
        BigDecimal value = requireExactly(operation, operands, 1).get(0);
        return normalize(BigDecimal.valueOf(function.apply(value.doubleValue())).setScale(SCALE, RoundingMode.HALF_UP));
    }

    private List<BigDecimal> requireAtLeast(Operation operation, List<BigDecimal> operands, int min) {
        if (operands.size() < min) {
            throw bad("CALC_INVALID_OPERAND_COUNT", operation.name() + " requires at least " + min + " operands");
        }
        return operands;
    }

    private List<BigDecimal> requireExactly(Operation operation, List<BigDecimal> operands, int count) {
        if (operands.size() != count) {
            throw bad("CALC_INVALID_OPERAND_COUNT", operation.name() + " requires exactly " + count + " operand(s)");
        }
        return operands;
    }

    private static boolean isZero(BigDecimal value) {
        return value.compareTo(BigDecimal.ZERO) == 0;
    }

    private static BigDecimal normalize(BigDecimal value) {
        BigDecimal result = value.stripTrailingZeros();
        if (result.scale() < 0) {
            result = result.setScale(0);
        }
        return result;
    }

    private static ApiException bad(String code, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message);
    }

    @FunctionalInterface
    private interface DoubleFunction {
        double apply(double value);
    }

    private final class Parser {
        private final String source;
        private int pos;

        private Parser(String source) {
            this.source = source;
        }

        BigDecimal parse() {
            BigDecimal result = parseExpression();
            skipWhitespace();
            if (pos != source.length()) {
                throw bad("CALC_INVALID_EXPRESSION", "Unexpected token at position " + pos);
            }
            return normalize(result);
        }

        private BigDecimal parseExpression() {
            BigDecimal result = parseTerm();
            while (true) {
                skipWhitespace();
                if (match('+')) {
                    result = result.add(parseTerm(), MC);
                } else if (match('-')) {
                    result = result.subtract(parseTerm(), MC);
                } else {
                    return normalize(result);
                }
            }
        }

        private BigDecimal parseTerm() {
            BigDecimal result = parsePower();
            while (true) {
                skipWhitespace();
                if (match('*')) {
                    result = result.multiply(parsePower(), MC);
                } else if (match('/')) {
                    result = divide(result, parsePower());
                } else if (match('%')) {
                    BigDecimal right = parsePower();
                    if (isZero(right)) {
                        throw bad("CALC_DIVIDE_BY_ZERO", "Modulo by zero is not allowed");
                    }
                    result = result.remainder(right, MC);
                } else {
                    return normalize(result);
                }
            }
        }

        private BigDecimal parsePower() {
            BigDecimal left = parseUnary();
            skipWhitespace();
            if (match('^')) {
                BigDecimal right = parsePower();
                return normalize(BigDecimal.valueOf(Math.pow(left.doubleValue(), right.doubleValue())).setScale(SCALE, RoundingMode.HALF_UP));
            }
            return left;
        }

        private BigDecimal parseUnary() {
            skipWhitespace();
            if (match('+')) {
                return parseUnary();
            }
            if (match('-')) {
                return parseUnary().negate(MC);
            }
            return parsePrimary();
        }

        private BigDecimal parsePrimary() {
            skipWhitespace();
            if (match('(')) {
                BigDecimal value = parseExpression();
                expect(')');
                return value;
            }
            if (peekLetter()) {
                String name = parseIdentifier();
                expect('(');
                BigDecimal first = parseExpression();
                skipWhitespace();
                if (match(',')) {
                    BigDecimal second = parseExpression();
                    expect(')');
                    return evaluateFunction(name, List.of(first, second));
                }
                expect(')');
                return evaluateFunction(name, List.of(first));
            }
            return parseNumber();
        }

        private BigDecimal evaluateFunction(String name, List<BigDecimal> args) {
            return evaluateOperation(name.toUpperCase(Locale.ROOT), args);
        }

        private BigDecimal parseNumber() {
            skipWhitespace();
            int start = pos;
            boolean dotSeen = false;
            while (pos < source.length()) {
                char ch = source.charAt(pos);
                if (Character.isDigit(ch)) {
                    pos++;
                } else if (ch == '.' && !dotSeen) {
                    dotSeen = true;
                    pos++;
                } else {
                    break;
                }
            }
            if (start == pos) {
                throw bad("CALC_INVALID_EXPRESSION", "Number expected at position " + pos);
            }
            try {
                return new BigDecimal(source.substring(start, pos), MC);
            } catch (NumberFormatException ex) {
                throw bad("CALC_INVALID_EXPRESSION", "Invalid number at position " + start);
            }
        }

        private String parseIdentifier() {
            int start = pos;
            while (pos < source.length() && Character.isLetter(source.charAt(pos))) {
                pos++;
            }
            return source.substring(start, pos);
        }

        private boolean match(char expected) {
            skipWhitespace();
            if (pos < source.length() && source.charAt(pos) == expected) {
                pos++;
                return true;
            }
            return false;
        }

        private void expect(char expected) {
            skipWhitespace();
            if (pos >= source.length() || source.charAt(pos) != expected) {
                throw bad("CALC_INVALID_EXPRESSION", "Expected '" + expected + "' at position " + pos);
            }
            pos++;
        }

        private boolean peekLetter() {
            skipWhitespace();
            return pos < source.length() && Character.isLetter(source.charAt(pos));
        }

        private void skipWhitespace() {
            while (pos < source.length() && Character.isWhitespace(source.charAt(pos))) {
                pos++;
            }
        }
    }
}
