package com.microapp.calculator;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RouteContractTest {

    @Test
    void onlyExpectedPublicRoutesAndBusinessBasePathAreDeclared() throws Exception {
        String system = Files.readString(Path.of("src/main/java/com/microapp/calculator/http/SystemController.java"));
        String calculator = Files.readString(Path.of("src/main/java/com/microapp/calculator/http/CalculatorController.java"));
        String security = Files.readString(Path.of("src/main/java/com/microapp/calculator/security/SecurityConfig.java"));

        assertTrue(system.contains("@GetMapping(\"/hello\")"));
        assertTrue(system.contains("@GetMapping(\"/health\")"));
        assertTrue(system.contains("@GetMapping(value = \"/docs\""));

        assertTrue(calculator.contains("@RequestMapping(\"/v1/calculator\")"));
        assertTrue(calculator.contains("@GetMapping(\"/operations\")"));
        assertTrue(calculator.contains("@PostMapping(\"/calculate\")"));
        assertTrue(calculator.contains("@GetMapping(\"/history\")"));
        assertTrue(calculator.contains("@GetMapping(\"/history/{userId}\")"));
        assertTrue(calculator.contains("@GetMapping(\"/records/{calculationId}\")"));
        assertTrue(calculator.contains("@DeleteMapping(\"/history\")"));

        assertTrue(security.contains("/hello"));
        assertTrue(security.contains("/health"));
        assertTrue(security.contains("/docs"));
        assertTrue(security.contains("/v1/**"));
    }

    @Test
    void openApiAndSwaggerGeneratedRoutesAreDisabled() throws Exception {
        String yml = Files.readString(Path.of("src/main/resources/application.yml"));

        assertTrue(yml.contains("springdoc:"));
        assertTrue(yml.contains("api-docs:"));
        assertTrue(yml.contains("enabled: false"));
        assertTrue(yml.contains("swagger-ui:"));
    }

    @Test
    void customRequestContextFilterDoesNotUseSpringBootReservedBeanName() throws Exception {
        String filter = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/http/RequestContextFilter.java")
        );

        assertTrue(filter.contains("@Component(\"calculatorRequestContextFilter\")"));
    }

    @Test
    void sharedObjectMapperBeanIsDeclared() throws Exception {
        String infrastructureConfig = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/config/InfrastructureConfig.java")
        );

        assertTrue(infrastructureConfig.contains("@Bean(\"calculatorObjectMapper\")"));
        assertTrue(infrastructureConfig.contains("@Primary"));
        assertTrue(infrastructureConfig.contains("public ObjectMapper objectMapper()"));
    }

    @Test
    void applicationYamlDoesNotUseRemovedJackson2DateSerializationProperty() throws Exception {
        String yml = Files.readString(Path.of("src/main/resources/application.yml"));

        assertFalse(yml.contains("write-dates-as-timestamps"));
    }

    @Test
    void applicationClassDoesNotUseRemovedSpringBootSecurityAutoConfigurationImport() throws Exception {
        String application = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/CalculatorServiceApplication.java")
        );

        assertFalse(application.contains("UserDetailsServiceAutoConfiguration"));
        assertFalse(application.contains("org.springframework.boot.autoconfigure.security.servlet"));
    }

    @Test
    void securityConfigDisablesGeneratedDefaultSecurityPasswordWithoutBootInternalImport() throws Exception {
        String security = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/security/SecurityConfig.java")
        );

        assertTrue(security.contains("UserDetailsService disabledUsernamePasswordUserDetailsService()"));
        assertTrue(security.contains("Username/password authentication is disabled"));
        assertTrue(security.contains("use Auth service Bearer JWT"));
    }
    @Test
    void elasticApmBootstrapsBeforeSpringAndKeepsDependencyInstrumentationEnabled() throws Exception {
        String application = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/CalculatorServiceApplication.java")
        );
        String bootstrap = Files.readString(
                Path.of("src/main/java/com/microapp/calculator/config/ElasticApmBootstrap.java")
        );

        assertTrue(application.contains("ElasticApmBootstrap.attachFromEnvironment()"));
        assertTrue(bootstrap.contains("metrics_interval"));
        assertTrue(bootstrap.contains("breakdown_metrics"));
        assertTrue(bootstrap.contains("global_labels"));
        assertFalse(bootstrap.contains("disable_instrumentations"));
    }


}
