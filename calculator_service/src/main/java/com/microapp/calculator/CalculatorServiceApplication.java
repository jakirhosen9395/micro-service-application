package com.microapp.calculator;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.config.ElasticApmBootstrap;
import com.microapp.calculator.config.EnvFileLoader;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
@EnableConfigurationProperties(AppProperties.class)
public class CalculatorServiceApplication {

    public static void main(String[] args) {
        EnvFileLoader.load();
        ElasticApmBootstrap.attachFromEnvironment();
        SpringApplication.run(CalculatorServiceApplication.class, args);
    }
}
