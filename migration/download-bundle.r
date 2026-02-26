library(connectapi)

# Connect to your "old" Posit Connect server
# Replace with your server URL and API key
connect <- connect(
  server = "http://localhost:3939",
  api_key = "yCVjvDM6IzGFboPdOhXN5wee4EM3CUZv"
)

admin_user <- "adminuser"

data_dir <- "/tmp/data"

dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

# the GUID of the admin user
my_guid <- get_users(connect, prefix = admin_user)$guid

# get guids of all deployed content
my_content <- get_content(connect)
my_content_guids <- my_content$guid


my_selected_content <- my_content[, c("guid", "name", "title", "vanity_url")]

user_lookup <- get_users(connect) |>
  dplyr::select(guid, username)

# get all current permissions of the content pieces
all_perms <- purrr::map(my_content_guids, \(content_guid) {
  item <- content_item(connect, content_guid)
  get_content_permissions(item) |>
    dplyr::left_join(user_lookup, by = c("principal_guid" = "guid"))
}) |>
  dplyr::bind_rows()

# save data in csv file so that target ownership can be added
write.csv(
  my_selected_content,
  file = file.path(data_dir, "relevant_content.csv")
)
write.csv(all_perms, file = file.path(data_dir, "relevant_content_perms.csv"))

message("Getting a list of all used R packages")
packs <- get_packages(connect) |>
  dplyr::filter(language == "r") |>
  dplyr::select(name) |>
  unique()
write.csv(packs, file = file.path(data_dir, "packages.csv"))


for (c_guid in my_content_guids) {
  # temporarily add admin_user to make download of bundle work
  message("Temporarily adding user ", admin_user, " to content ", c_guid)
  tryCatch(
    content_add_user(content_item(connect, c_guid), my_guid, role = "owner"),
    error = function(e) {
      message("Skipping guid ", c_guid, ": ", conditionMessage(e))
    }
  )

  # get name of content
  bundles <- get_bundles(content_item(connect, c_guid))
  guid_name <- my_selected_content |>
    dplyr::filter(guid == c_guid) |>
    dplyr::pull(name)
  message("Working on content ", c_guid, " / ", guid_name)
  bundle_count <- nrow(bundles)
  ctr <- 0

  # download all bundles
  for (bundle in bundles$id) {
    ctr <- ctr + 1
    filename <- file.path(
      data_dir,
      paste0("bundle-", c_guid, "-", ctr, ".tar.gz")
    )
    message(". Extracting bundle ", ctr, "/", bundle_count, " into ", filename)
    download_bundle(
      content_item(connect, c_guid),
      filename = filename,
      bundle_id = bundle,
      overwrite = TRUE
    )
  }

  # Remove temp owner AFTER all bundles are downloaded
  message(
    ". Removing temporarily added user ",
    admin_user,
    " from content ",
    c_guid
  )
  tryCatch(
    content_delete_user(content_item(connect, c_guid), my_guid),
    error = function(e) {
      message("Skipping delete for guid ", c_guid, ": ", conditionMessage(e))
    }
  )
  message(" ")
}
