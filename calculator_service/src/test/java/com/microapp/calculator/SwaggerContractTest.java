package com.microapp.calculator;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.http.DocsHtml;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SwaggerContractTest {

    @Test
    void docsHtmlEmbedsOnlySwaggerUiWithoutCustomGuideHeader() {
        String html = DocsHtml.html(docsProps());

        assertTrue(html.contains("SwaggerUIBundle"));
        assertTrue(html.contains("Calculator Service API"));
        assertTrue(html.contains("swagger-ui-dist@5.19.0"));
        assertTrue(html.contains("<div id=\"swagger-ui\"></div>"));

        assertFalse(html.contains("<section class=\"guide\">"));
        assertFalse(html.contains("Calculator Service API Console"));
        assertFalse(html.contains("How to use"));
        assertFalse(html.contains("Authorization and side effects"));
        assertFalse(html.contains("Only public docs route"));
        assertFalse(html.contains("Environment: <code>"));
        assertFalse(html.contains("Base URL: <code>same origin</code>"));
    }

    @Test
    void docsHtmlKeepsSwaggerUsableWithAuthorizeAndTryItOut() {
        String html = DocsHtml.html(docsProps());

        assertTrue(html.contains("persistAuthorization: true"));
        assertTrue(html.contains("tryItOutEnabled: true"));
        assertTrue(html.contains("supportedSubmitMethods"));
        assertTrue(html.contains("validatorUrl: null"));
        assertTrue(html.contains("syntaxHighlight"));
        assertTrue(html.contains("activated: false"));
        assertTrue(html.contains("requestInterceptor"));
        assertTrue(html.contains("responseInterceptor"));

        assertTrue(html.contains("X-Request-ID"));
        assertTrue(html.contains("X-Trace-ID"));
        assertTrue(html.contains("X-Correlation-ID"));
        assertTrue(html.contains("safeRandomId"));

        assertTrue(html.contains("bearerAuth"));
        assertTrue(html.contains("\"type\": \"http\""));
        assertTrue(html.contains("\"scheme\": \"bearer\""));
        assertTrue(html.contains("\"bearerFormat\": \"JWT\""));
        assertTrue(html.contains("Paste only the access_token value"));
        assertTrue(html.contains("normalizeAuthorizationHeader"));
        assertTrue(html.contains("Bearer " + "<token>"));

        assertTrue(html.contains("window.location.origin"));
        assertTrue(html.contains("rel=\"icon\" href=\"data:,\""));

        assertFalse(html.contains("HideBrokenSwaggerResponsesPlugin"));
        assertFalse(html.contains("removeSwaggerResponseRendererErrors"));
        assertFalse(html.contains("wrapComponents"));
        assertFalse(html.contains("responses: () => () => null"));
    }

    @Test
    void docsHtmlDoesNotExposeGeneratedOpenApiOrSwaggerUiRoutesAsSpecPaths() {
        String html = DocsHtml.html(docsProps());

        assertTrue(html.contains("\"/docs\""));

        assertFalse(html.contains("\"/openapi.json\""));
        assertFalse(html.contains("\"/v3/api-docs\""));
        assertFalse(html.contains("\"/swagger-ui"));
        assertFalse(html.contains("http://localhost:8080"));
        assertFalse(html.contains("http://192.168.56.100:2020"));
    }

    @Test
    void openApiSpecUsesDescriptionOnlyResponsesToAvoidSwaggerRendererFailures() {
        String html = DocsHtml.html(docsProps());

        assertTrue(html.contains("\"responses\""));
        assertTrue(html.contains("\"200\""));
        assertTrue(html.contains("\"400\""));
        assertTrue(html.contains("\"401\""));
        assertTrue(html.contains("\"403\""));
        assertTrue(html.contains("\"404\""));

        assertFalse(html.contains("\"$ref\": \"#/components/schemas/SuccessEnvelope\""));
        assertFalse(html.contains("\"$ref\": \"#/components/schemas/ErrorEnvelope\""));
        assertFalse(html.contains("#/components/responses"));
        assertFalse(html.contains("\"$ref\": \"#/components/responses"));
        assertFalse(html.contains("\"data\": {}"));
        assertFalse(html.contains("\"details\": {}"));
        assertFalse(html.contains("additionalProperties"));
    }

    @Test
    void docsHtmlContainsAllExpectedCalculatorRoutes() {
        String html = DocsHtml.html(docsProps());

        assertTrue(html.contains("\"/hello\""));
        assertTrue(html.contains("\"/health\""));
        assertTrue(html.contains("\"/docs\""));
        assertTrue(html.contains("\"/v1/calculator/operations\""));
        assertTrue(html.contains("\"/v1/calculator/calculate\""));
        assertTrue(html.contains("\"/v1/calculator/history\""));
        assertTrue(html.contains("\"/v1/calculator/history/{userId}\""));
        assertTrue(html.contains("\"/v1/calculator/records/{calculationId}\""));
    }

    @Test
    void docsHtmlContainsExpectedRequestSchemasAndExamples() {
        String html = DocsHtml.html(docsProps());

        assertTrue(html.contains("\"CalculateRequestOperation\""));
        assertTrue(html.contains("\"CalculateRequestExpression\""));
        assertFalse(html.contains("\"SuccessEnvelope\""));
        assertFalse(html.contains("\"ErrorEnvelope\""));

        assertTrue(html.contains("\"operation\": \"ADD\""));
        assertTrue(html.contains("\"operands\": [10, 20]"));
        assertTrue(html.contains("\"expression\": \"sqrt(16)+(10+5)*3\""));
    }

    private static AppProperties docsProps() {
        AppProperties props = new AppProperties();
        props.setServiceName("calculator_service");
        props.setEnvironment("development");
        props.setVersion("v1.0.0");
        props.setTenant("dev");
        return props;
    }
}
