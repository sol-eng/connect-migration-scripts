library(pak)

# This code will print out system commands to run that will install
# the necessary system dependencies needed for the R packages
# in the upcoming deployments

data_dir <- "/tmp/data"

packs <- read.csv(file.path(data_dir, "packages.csv"))

sysreqs <- pak::pkg_sysreqs(packs$name)
message(
  "Please install the system requirements using the commands below so that the new deployments will work"
)
if (length(sysreqs$pre_install) > 0) {
  cat(sysreqs$pre_install, fill = TRUE)
}
if (length(sysreqs$install_scripts) > 0) {
  cat(sysreqs$install_scripts, fill = TRUE)
}
if (length(sysreqs$post_install) > 0) {
  cat(sysreqs$post_install, fill = TRUE)
}

if (
  length(sysreqs$pre_install) +
    length(sysreqs$install_scripts) +
    length(sysreqs$post_install) >
    0
) {
  cat
  "Please make sure the above system requirements are installed before proceeding"
  break
}

cat("✓ All system requirements are met.\n\n")
