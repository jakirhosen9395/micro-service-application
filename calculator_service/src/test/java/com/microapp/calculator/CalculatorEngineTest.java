package com.microapp.calculator;

import com.microapp.calculator.domain.CalculatorEngine;
import com.microapp.calculator.domain.Operation;
import com.microapp.calculator.exception.ApiException;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class CalculatorEngineTest {
    private final CalculatorEngine engine = new CalculatorEngine();

    @Test
    void supportsAllRequiredOperationNames() {
        for (String operation : List.of("ADD", "SUBTRACT", "MULTIPLY", "DIVIDE", "MODULO", "POWER", "SQRT", "PERCENTAGE", "SIN", "COS", "TAN", "LOG", "LN", "ABS", "ROUND", "FLOOR", "CEIL", "FACTORIAL")) {
            assertNotNull(Operation.valueOf(operation));
        }
    }

    @Test
    void supportsOperationMode() {
        assertEquals("30", engine.evaluateOperation("ADD", List.of(new BigDecimal("10"), new BigDecimal("20"))).toPlainString());
        assertEquals("-10", engine.evaluateOperation("SUBTRACT", List.of(new BigDecimal("10"), new BigDecimal("20"))).toPlainString());
        assertEquals("200", engine.evaluateOperation("MULTIPLY", List.of(new BigDecimal("10"), new BigDecimal("20"))).toPlainString());
        assertEquals("5", engine.evaluateOperation("DIVIDE", List.of(new BigDecimal("10"), new BigDecimal("2"))).toPlainString());
        assertEquals("1", engine.evaluateOperation("MODULO", List.of(new BigDecimal("10"), new BigDecimal("3"))).toPlainString());
        assertEquals("8", engine.evaluateOperation("POWER", List.of(new BigDecimal("2"), new BigDecimal("3"))).toPlainString());
        assertEquals("4", engine.evaluateOperation("SQRT", List.of(new BigDecimal("16"))).toPlainString());
        assertEquals("45", engine.evaluateOperation("PERCENTAGE", List.of(new BigDecimal("10"), new BigDecimal("450"))).toPlainString());
        assertEquals("10", engine.evaluateOperation("ABS", List.of(new BigDecimal("-10"))).toPlainString());
        assertEquals("3", engine.evaluateOperation("ROUND", List.of(new BigDecimal("2.5"))).toPlainString());
        assertEquals("2", engine.evaluateOperation("FLOOR", List.of(new BigDecimal("2.9"))).toPlainString());
        assertEquals("3", engine.evaluateOperation("CEIL", List.of(new BigDecimal("2.1"))).toPlainString());
        assertEquals("120", engine.evaluateOperation("FACTORIAL", List.of(new BigDecimal("5"))).toPlainString());
    }

    @Test
    void supportsExpressionMode() {
        assertEquals("49", engine.evaluateExpression("sqrt(16)+(10+5)*3").toPlainString());
        assertEquals("14", engine.evaluateExpression("2+3*4").toPlainString());
        assertEquals("512", engine.evaluateExpression("power(2,3)^3").toPlainString());
    }

    @Test
    void rejectsUnsafeOrInvalidInputs() {
        assertError("CALC_DIVIDE_BY_ZERO", () -> engine.evaluateOperation("DIVIDE", List.of(BigDecimal.ONE, BigDecimal.ZERO)));
        assertError("CALC_DIVIDE_BY_ZERO", () -> engine.evaluateExpression("1/0"));
        assertError("CALC_NEGATIVE_SQUARE_ROOT", () -> engine.evaluateOperation("SQRT", List.of(new BigDecimal("-1"))));
        assertError("CALC_INVALID_LOGARITHM", () -> engine.evaluateOperation("LOG", List.of(BigDecimal.ZERO)));
        assertError("CALC_INVALID_FACTORIAL", () -> engine.evaluateOperation("FACTORIAL", List.of(new BigDecimal("2.5"))));
        assertError("CALC_INVALID_OPERATION", () -> engine.evaluateOperation("NOPE", List.of(BigDecimal.ONE)));
        assertError("CALC_INVALID_OPERAND_COUNT", () -> engine.evaluateOperation("ADD", List.of(BigDecimal.ONE)));
        assertError("CALC_INVALID_EXPRESSION", () -> engine.evaluateExpression("sqrt(16)+"));
    }

    private static void assertError(String code, Executable executable) {
        ApiException ex = assertThrows(ApiException.class, executable::run);
        assertEquals(code, ex.errorCode());
    }

    @FunctionalInterface
    private interface Executable {
        void run();
    }
}
