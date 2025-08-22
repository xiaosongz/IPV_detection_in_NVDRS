test_that("reconcile_le_cme handles both results", {
  le_result <- list(ipv_detected = TRUE, confidence = 0.8)
  cme_result <- list(ipv_detected = FALSE, confidence = 0.3)
  weights <- list(le = 0.4, cme = 0.6, threshold = 0.5)
  
  result <- reconcile_le_cme(le_result, cme_result, weights)
  
  expected_confidence <- 0.8 * 0.4 + 0.3 * 0.6
  expect_equal(result$confidence, expected_confidence)
  expect_equal(result$ipv_detected, expected_confidence >= 0.5)
})

test_that("reconcile_le_cme handles missing LE", {
  le_result <- list(ipv_detected = NA, confidence = NA)
  cme_result <- list(ipv_detected = TRUE, confidence = 0.9)
  weights <- list(le = 0.4, cme = 0.6, threshold = 0.5)
  
  result <- reconcile_le_cme(le_result, cme_result, weights)
  expect_equal(result$ipv_detected, TRUE)
  expect_equal(result$confidence, 0.9)
})

test_that("calculate_agreement handles all cases", {
  results <- data.frame(
    le_ipv = c(TRUE, TRUE, FALSE, FALSE, NA),
    cme_ipv = c(TRUE, FALSE, FALSE, TRUE, TRUE)
  )
  
  agreement <- calculate_agreement(results)
  expect_equal(agreement$n, 4)  # 4 valid pairs
  expect_equal(agreement$both_positive, 1)
  expect_equal(agreement$both_negative, 1)
  expect_equal(agreement$le_only, 1)
  expect_equal(agreement$cme_only, 1)
  expect_equal(agreement$agreement_rate, 0.5)
})