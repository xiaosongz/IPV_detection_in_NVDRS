test_that("read_nvdrs_data handles missing file", {
  expect_error(read_nvdrs_data("nonexistent.csv"), "File not found")
})

test_that("validate_input_data removes empty narratives", {
  data <- data.frame(
    IncidentID = c("1", "2", "3"),
    NarrativeLE = c("text", NA, NA),
    NarrativeCME = c("text", NA, "text"),
    stringsAsFactors = FALSE
  )
  
  validated <- validate_input_data(data)
  expect_equal(nrow(validated), 2)  # Should remove row 2
})

test_that("split_into_batches creates correct batches", {
  data <- data.frame(
    IncidentID = 1:100,
    NarrativeLE = rep("text", 100),
    NarrativeCME = rep("text", 100)
  )
  
  batches <- split_into_batches(data, batch_size = 30)
  expect_equal(length(batches), 4)  # 100/30 = 3.33 -> 4 batches
  expect_equal(nrow(batches[[1]]), 30)
  expect_equal(nrow(batches[[4]]), 10)
})

test_that("trimws is applied to narratives", {
  data <- data.frame(
    IncidentID = "1",
    NarrativeLE = "  text with spaces  ",
    NarrativeCME = "\ttext with tabs\t",
    stringsAsFactors = FALSE
  )
  
  # Create temp file
  tmp <- tempfile(fileext = ".csv")
  write.csv(data, tmp, row.names = FALSE)
  
  result <- read_nvdrs_data(tmp)
  expect_equal(result$NarrativeLE, "text with spaces")
  expect_equal(result$NarrativeCME, "text with tabs")
  
  unlink(tmp)
})