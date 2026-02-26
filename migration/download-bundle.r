library(connectapi)
library(furrr)

# Connect to your "old" Posit Connect server
# Replace with your server URL and API key
connect <- connect(
  server = "http://localhost:3939",
  api_key = "m9bkMPuVwCVebFke2fZ0B4jYB8kR3tMw"
)

admin_user <- "adminuser"

data_dir <- "/tmp/data"

# On Connect servers with HideVersions=TRUE configured, vanity_url is not directly exposed
# and a workaround is needed. Setting this to FALSE should be the default.
is_hide_version <- TRUE

# If is_fda_testing is set to
#   TRUE: only download the bundles of the m5-perf and the penguins app
#   FALSE: download everything
is_fda_testing <- TRUE

# Only download max_bundles_per_guid
max_bundles_per_guid <- 10

dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

# the GUID of the admin user
my_guid <- get_users(connect, prefix = admin_user)$guid

# get guids of all deployed content
my_content <- get_content(connect)
my_content_guids <- my_content$guid


# my_selected_content <- my_content[, c("guid", "name", "title", "vanity_url")]
my_selected_content <- my_content[, c("guid", "name", "title")]

my_selected_content <- my_content[, c("guid", "name", "title")] |>
  dplyr::mutate(
    vanity_url = purrr::map_chr(guid, \(g) {
      result <- get_vanity_url(content_item(connect, g))
      if (is.null(result)) NA_character_ else result
    })
  )

if (is_hide_version) {
  # connect does not expose the vanity_url via the get_content() function if
  # HideVersion=TRUE, hence we need to spearaltely loop through
  # the get_vanity_url() function
  my_selected_content <- my_content[, c("guid", "name", "title")]

  plan(multisession, workers = 4)
  my_selected_content$vanity_url <- future_map_chr(
    my_selected_content$guid,
    \(g) {
      cat("Processing", g, "\n")
      result <- get_vanity_url(content_item(connect, g))
      if (is.null(result)) NA_character_ else result
    },
    .progress = TRUE,
    .options = furrr_options(seed = NULL)
  )
  plan(sequential)
} else {
  my_selected_content <- my_content[, c("guid", "name", "title", "vanity_url")]
}

#get_vanity_url( content_item(connect, "410c782c-a8bf-480d-8238-dced02145e67"))

user_lookup <- get_users(connect) |>
  dplyr::select(guid, username)

group_lookup <- get_groups(connect) |>
  dplyr::select(guid, name) |>
  dplyr::rename(groupname = name)

# get all current permissions of the content pieces
all_perms <- purrr::map(my_content_guids, \(content_guid) {
  item <- content_item(connect, content_guid)
  perms <- get_content_permissions(item)

  # Add user or group names based on principal_type
  perms |>
    dplyr::left_join(
      user_lookup,
      by = c("principal_guid" = "guid")
    ) |>
    dplyr::left_join(
      group_lookup,
      by = c("principal_guid" = "guid")
    ) |>
    dplyr::mutate(
      principal_name = dplyr::case_when(
        principal_type == "user" ~ username,
        principal_type == "group" ~ groupname,
        TRUE ~ NA_character_
      )
    ) |>
    dplyr::select(-username, -groupname)
}) |>
  dplyr::bind_rows()

# save data in csv file so that target ownership can be added
write.csv(
  my_selected_content,
  file = file.path(data_dir, "relevant_content.csv")
)
write.csv(all_perms, file = file.path(data_dir, "relevant_content_perms.csv"))

# Get environment variable names for each content item
message("Getting environment variables for all content items")
all_env_vars <- purrr::map(my_content_guids, \(content_guid) {
  item <- content_item(connect, content_guid)
  env <- get_environment(item)
  env_names <- unlist(env$env_vars)
  if (length(env_names) == 0) {
    return(tibble::tibble(
      content_guid = character(),
      env_var_name = character()
    ))
  }
  tibble::tibble(
    content_guid = content_guid,
    env_var_name = as.character(env_names)
  )
}) |>
  dplyr::bind_rows()

write.csv(
  all_env_vars,
  file = file.path(data_dir, "content_env_vars.csv"),
  row.names = FALSE
)
message(
  "Saved ",
  nrow(all_env_vars),
  " environment variables to content_env_vars.csv"
)

message("Getting a list of all used R packages")
packs <- get_packages(connect) |>
  dplyr::filter(language == "r") |>
  dplyr::select(name) |>
  unique()
write.csv(packs, file = file.path(data_dir, "packages.csv"))

plan(multisession, workers = 4)

if (is_fda_testing) {
  my_content_guids <- c(
    "ceb8c9c6-0bbf-4c3b-b968-9baa1b9c023a",
    "dbf14418-b901-4d9f-b396-5bc82ec21075"
  )
}

future_walk(
  my_content_guids,
  \(c_guid) {
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
      message(
        ". Extracting bundle ",
        ctr,
        "/",
        bundle_count,
        " into ",
        filename
      )
      download_bundle(
        content_item(connect, c_guid),
        filename = filename,
        bundle_id = bundle,
        overwrite = TRUE
      )

      if (ctr >= max_bundles_per_guid) {
        break
      }
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
  },
  .progress = TRUE,
  .options = furrr_options(seed = NULL)
)

plan(sequential)
