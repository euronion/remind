# |  (C) 2006-2023 Potsdam Institute for Climate Impact Research (PIK)
# |  authors, and contributors see CITATION.cff file. This file is part
# |  of REMIND and licensed under AGPL-3.0-or-later. Under Section 7 of
# |  AGPL-3.0, you are granted additional permissions described in the
# |  REMIND License Exception, version 1.0 (see LICENSE file).
# |  Contact: remind@pik-potsdam.de
test_that("runGamsCompile works", {
  source("../../config/default.cfg")
  gmsfile <- tempfile(fileext = ".gms")
  writeLines(c("Parameter test 'a great test value' / 4 /;"), gmsfile)
  expect_true(runGamsCompile(gmsfile, cfg, interactive = FALSE))
  writeLines(c("meter test 'a great test value' / 4 /"), gmsfile)
  expect_false(runGamsCompile(gmsfile, cfg, interactive = FALSE))
})
