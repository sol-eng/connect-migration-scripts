library(connectapi)
library(furrr)

connect_new <- connect(
  server = "http://localhost:3940",
  api_key = "DO8QaoKqDHkK6IhXir8tJnhECjAXj4QQ"
)

admin_user <- "adminuser"
data_dir <- "/tmp/data"

create_missing_users_and_groups <- TRUE

# Load permissions data for validation
content_perms <- read.csv(file.path(data_dir, "relevant_content_perms.csv"))

# Check if all required users and groups exist on target server
cat("Validating users and groups on target server...\n")

# Get all users and groups from target server
target_users <- get_users(connect_new)
target_groups <- get_groups(connect_new)

# Get unique principals from permissions data (excluding admin user)
required_principals <- content_perms |>
  dplyr::filter(principal_name != admin_user) |>
  dplyr::select(principal_name, principal_type) |>
  dplyr::distinct()

missing_principals <- c()

# Load source server user/group data for creating missing principals
source_users <- tryCatch(
  read.csv(file.path(data_dir, "users.csv")),
  error = function(e) NULL
)
source_groups <- tryCatch(
  read.csv(file.path(data_dir, "groups.csv")),
  error = function(e) NULL
)
source_group_members <- tryCatch(
  read.csv(file.path(data_dir, "group_members.csv")),
  error = function(e) NULL
)

for (i in seq_len(nrow(required_principals))) {
  principal <- required_principals[i, ]

  if (principal$principal_type == "user") {
    if (!any(target_users$username == principal$principal_name)) {
      if (create_missing_users_and_groups && !is.null(source_users)) {
        user_info <- source_users |>
          dplyr::filter(username == principal$principal_name)
        if (nrow(user_info) > 0) {
          cat("  Creating missing user:", principal$principal_name, "\n")
          tryCatch(
            {
              connect_new$POST(
                "v1/users",
                body = list(
                  username = user_info$username[1],
                  first_name = user_info$first_name[1],
                  last_name = user_info$last_name[1],
                  email = user_info$email[1],
                  password = "changeme!"
                )
              )
              cat("  ✓ Created user:", principal$principal_name, "\n")
            },
            error = function(e) {
              cat(
                "  ✗ Failed to create user:",
                principal$principal_name,
                "-",
                e$message,
                "\n"
              )
              missing_principals <<- c(
                missing_principals,
                paste0("USER: ", principal$principal_name)
              )
            }
          )
        } else {
          cat("  ✗ No source data for user:", principal$principal_name, "\n")
          missing_principals <- c(
            missing_principals,
            paste0("USER: ", principal$principal_name)
          )
        }
      } else {
        missing_principals <- c(
          missing_principals,
          paste0("USER: ", principal$principal_name)
        )
      }
    }
  } else if (principal$principal_type == "group") {
    if (!any(target_groups$name == principal$principal_name)) {
      if (create_missing_users_and_groups && !is.null(source_groups)) {
        cat("  Creating missing group:", principal$principal_name, "\n")
        tryCatch(
          {
            connect_new$POST(
              "v1/groups",
              body = list(
                name = principal$principal_name
              )
            )
            cat("  ✓ Created group:", principal$principal_name, "\n")

            # Add members to the group if we have membership data
            if (!is.null(source_group_members)) {
              members <- source_group_members |>
                dplyr::filter(group_name == principal$principal_name)
              if (nrow(members) > 0) {
                # Refresh target users list to include newly created users
                target_users_refreshed <- get_users(connect_new)
                new_group <- get_groups(
                  connect_new,
                  prefix = principal$principal_name
                )
                for (m in seq_len(nrow(members))) {
                  member_guid <- target_users_refreshed |>
                    dplyr::filter(username == members$username[m]) |>
                    dplyr::pull(guid)
                  if (length(member_guid) > 0) {
                    tryCatch(
                      {
                        connect_new$POST(
                          paste0("v1/groups/", new_group$guid[1], "/members"),
                          body = list(user_guid = member_guid[1])
                        )
                        cat("    ✓ Added", members$username[m], "to group\n")
                      },
                      error = function(e) {
                        cat(
                          "    ✗ Failed to add",
                          members$username[m],
                          "to group:",
                          e$message,
                          "\n"
                        )
                      }
                    )
                  } else {
                    cat(
                      "    ✗ User",
                      members$username[m],
                      "not found on target server\n"
                    )
                  }
                }
              }
            }
          },
          error = function(e) {
            cat(
              "  ✗ Failed to create group:",
              principal$principal_name,
              "-",
              e$message,
              "\n"
            )
            missing_principals <<- c(
              missing_principals,
              paste0("GROUP: ", principal$principal_name)
            )
          }
        )
      } else {
        missing_principals <- c(
          missing_principals,
          paste0("GROUP: ", principal$principal_name)
        )
      }
    }
  }
}

if (length(missing_principals) > 0) {
  cat("ERROR: The following users/groups are missing on target server:\n")
  for (missing in missing_principals) {
    cat("  -", missing, "\n")
  }
  cat("\nPlease create these users/groups before running the migration.\n")
  stop("Migration aborted due to missing users/groups")
}

cat("✓ All required users and groups exist on target server\n\n")

# Create "migrated" tag on target server
cat("Creating 'migrated' tag on target server...\n")
migrated_tag <- tryCatch(
  {
    create_tag(connect_new, "migrated")
  },
  error = function(e) {
    # Tag may already exist, try to find it
    tags <- get_tags(connect_new)
    tags$migrated
  }
)
cat("✓ 'migrated' tag ready\n\n")

bundle_files <- list.files(
  path = data_dir,
  pattern = "^bundle.*\\.tar\\.gz$",
  full.names = TRUE
) |>
  # Sort files properly by extracting and ordering the numeric suffix
  {
    \(files) {
      # Create a data frame with file paths and extracted bundle numbers
      bundle_data <- tibble::tibble(file = files) |>
        dplyr::mutate(
          # Extract the bundle number (last number before .tar.gz)
          bundle_num = as.numeric(stringr::str_extract(
            basename(file),
            "-(\\d+)\\.tar\\.gz$",
            group = 1
          ))
        ) |>
        dplyr::arrange(bundle_num)

      bundle_data$file
    }
  }()

relevant_content <- read.csv(file.path(data_dir, "relevant_content.csv"))
# content_perms already loaded above for validation

# Load environment variables
env_vars_file <- file.path(data_dir, "content_env_vars.csv")
if (file.exists(env_vars_file)) {
  content_env_vars <- read.csv(env_vars_file)
  cat("Loaded", nrow(content_env_vars), "environment variable entries\n")
} else {
  content_env_vars <- tibble::tibble(
    content_guid = character(),
    name = character(),
    env_var_name = character(),
    env_var_value = character()
  )
  cat("No environment variables file found, skipping env vars\n")
}

# Group bundle files by GUID
bundle_df <- tibble::tibble(file = bundle_files) |>
  dplyr::mutate(
    guid = purrr::map_chr(file, \(f) {
      paste(strsplit(basename(f), "-")[[1]][2:6], collapse = "-")
    })
  )

# Helper function to deploy all bundles for a single GUID and set permissions
deploy_guid <- function(
  guid,
  guid_bundles,
  metadata,
  content_perms,
  connect_new,
  admin_user,
  content_env_vars,
  migrated_tag
) {
  has_multiple <- nrow(guid_bundles) > 1

  # Deploy in reverse order so the lowest-numbered bundle is deployed last (becomes active)
  if (has_multiple) {
    guid_bundles <- guid_bundles |> dplyr::arrange(dplyr::desc(file))
  }

  new_bundle_id <- NULL
  first_bundle_deployed <- FALSE

  for (bundle_file in guid_bundles$file) {
    cat("  Deploying bundle:", basename(bundle_file), "\n")
    bundle <- NULL
    tryCatch(
      {
        bundle <- bundle_path(bundle_file)
        cat("  Metadata - Name:", as.character(metadata$name), "\n")
        cat("  Metadata - Title:", as.character(metadata$title), "\n")

        new_bundle_id <- deploy(
          connect_new,
          bundle,
          title = as.character(metadata$title),
          name = as.character(metadata$name)
        )
        cat(
          "  Successfully started deployment:",
          new_bundle_id$content$guid,
          "\n"
        )

        # Poll after first bundle deployment OR if multiple bundles for this GUID
        if (!first_bundle_deployed || has_multiple) {
          cat("  Waiting for deployment to complete...\n")
          poll_task(new_bundle_id, wait = 2, callback = NULL)
          cat("  Deployment complete, proceeding to next bundle.\n")
          first_bundle_deployed <- TRUE
        }
      },
      error = function(e) {
        cat("  Error deploying bundle:", e$message, "\n")
      },
      finally = {
        # Close only file connections opened by bundle_path/deploy
        open_cons <- showConnections(all = FALSE)
        if (nrow(open_cons) > 0) {
          file_cons <- which(
            open_cons[, "class"] == "file" &
              grepl("\\.tar\\.gz$", open_cons[, "description"])
          )
          for (con_idx in as.integer(rownames(open_cons)[file_cons])) {
            tryCatch(close(getConnection(con_idx)), error = function(e) NULL)
          }
        }
        gc()
      }
    )
  }

  if (is.null(new_bundle_id)) {
    cat("  No successful deployment for", guid, "\n\n")
    return(invisible(NULL))
  }

  new_content <- content_item(connect_new, new_bundle_id$content$guid)

  # Set vanity URL if defined
  vanity <- as.character(metadata$vanity_url)
  if (!is.na(vanity) && nchar(vanity) > 0) {
    vanity_path <- httr::parse_url(vanity)$path
    tryCatch(
      {
        set_vanity_url(new_content, vanity_path, force = TRUE)
        cat("  Set vanity URL:", vanity_path, "\n")
      },
      error = function(e) {
        cat("  Error setting vanity URL:", e$message, "\n")
      }
    )
  }

  # Apply permissions from the old server
  old_guid_perms <- content_perms |>
    dplyr::filter(content_guid == guid, principal_name != admin_user)

  for (i in seq_len(nrow(old_guid_perms))) {
    perm <- old_guid_perms[i, ]
    tryCatch(
      {
        if (perm$principal_type == "user") {
          target_guid <- user_guid_from_username(
            connect_new,
            perm$principal_name
          )
          if (!is.na(target_guid)) {
            content_add_user(new_content, target_guid, role = perm$role)
            cat("  Added user", perm$principal_name, "as", perm$role, "\n")
          } else {
            cat("  User not found on target server:", perm$principal_name, "\n")
          }
        } else if (perm$principal_type == "group") {
          # Find group by name
          target_groups <- get_groups(connect_new, prefix = perm$principal_name)
          if (nrow(target_groups) > 0) {
            target_guid <- target_groups$guid[1]
            content_add_group(new_content, target_guid, role = perm$role)
            cat("  Added group", perm$principal_name, "as", perm$role, "\n")
          } else {
            cat(
              "  Group not found on target server:",
              perm$principal_name,
              "\n"
            )
          }
        }
      },
      error = function(e) {
        cat(
          "  Error adding permission for",
          perm$principal_name,
          "(",
          perm$principal_type,
          "):",
          e$message,
          "\n"
        )
      }
    )
  }

  # Transfer ownership
  owner_row <- content_perms |>
    dplyr::filter(
      content_guid == guid,
      role == "owner",
      principal_name != admin_user
    )

  if (nrow(owner_row) >= 1) {
    owner_principal <- owner_row[1, ]
    tryCatch(
      {
        if (owner_principal$principal_type == "user") {
          new_owner_guid <- user_guid_from_username(
            connect_new,
            owner_principal$principal_name
          )
          if (!is.na(new_owner_guid)) {
            content_update_owner(new_content, new_owner_guid)
            cat(
              "  Ownership transferred to user",
              owner_principal$principal_name,
              "\n"
            )
          }
        } else {
          cat(
            "  WARNING: Cannot transfer ownership to group",
            owner_principal$principal_name,
            "\n"
          )
        }
      },
      error = function(e) {
        cat("  Error transferring ownership:", e$message, "\n")
      }
    )
  } else {
    cat(
      "  WARNING: No owner found for",
      guid,
      "- adminuser will remain as owner\n"
    )
  }

  # Remove admin user
  tryCatch(
    {
      my_guid <- user_guid_from_username(connect_new, admin_user)
      content_delete_user(new_content, my_guid)
      cat("  Removed", admin_user, "from content\n")
    },
    error = function(e) {
      cat("  Error removing admin user:", e$message, "\n")
    }
  )

  # Apply environment variables
  guid_env_vars <- content_env_vars |>
    dplyr::filter(content_guid == guid)

  if (nrow(guid_env_vars) > 0) {
    env_args <- list()
    for (j in seq_len(nrow(guid_env_vars))) {
      var_name <- guid_env_vars$env_var_name[j]
      var_value <- guid_env_vars$env_var_value[j]
      env_args[[var_name]] <- var_value
    }
    if (length(env_args) > 0) {
      tryCatch(
        {
          do.call(set_environment_all, c(list(new_content), env_args))
          cat(
            "  Set environment variables:",
            paste(names(env_args), collapse = ", "),
            "\n"
          )
        },
        error = function(e) {
          cat("  Error setting environment variables:", e$message, "\n")
        }
      )
    }
  }

  # Tag content as "migrated"
  tryCatch(
    {
      set_content_tags(new_content, migrated_tag)
      cat("  Tagged content as 'migrated'\n")
    },
    error = function(e) {
      cat("  Error tagging content:", e$message, "\n")
    }
  )

  cat("\n")
  invisible(new_bundle_id)
}

# Process all GUIDs — each GUID is independent, fire-and-forget
# Multi-bundle GUIDs self-manage sequencing via poll_task
guids <- unique(bundle_df$guid)

# Deploy first GUID sequentially to avoid packrat locking issues
first_guid <- guids[1]
cat("Processing first GUID sequentially:", first_guid, "\n")

if (!any(relevant_content$guid == first_guid)) {
  cat("Warning: No metadata found for GUID:", first_guid, "\n\n")
} else {
  metadata <- relevant_content[relevant_content$guid == first_guid, ]
  guid_bundles <- bundle_df |> dplyr::filter(guid == !!first_guid)

  deploy_guid(
    first_guid,
    guid_bundles,
    metadata,
    content_perms,
    connect_new,
    admin_user,
    content_env_vars,
    migrated_tag
  )
}

# Deploy remaining GUIDs in parallel
remaining_guids <- guids[-1]

if (length(remaining_guids) > 0) {
  cat("Processing remaining", length(remaining_guids), "GUIDs in parallel\n")

  # Pass connection details instead of the R6 object
  # so each worker can create its own connection (needed for multisession/Windows)
  connect_server <- connect_new$server
  connect_api_key <- connect_new$api_key

  plan(multisession, workers = 3)

  future_walk(
    remaining_guids,
    \(guid) {
      # Create a fresh connection in each worker
      worker_connect <- connectapi::connect(
        server = connect_server,
        api_key = connect_api_key
      )

      cat("Processing GUID:", guid, "\n")

      if (!any(relevant_content$guid == guid)) {
        cat("Warning: No metadata found for GUID:", guid, "\n\n")
        return(invisible(NULL))
      }

      metadata <- relevant_content[relevant_content$guid == guid, ]
      guid_bundles <- bundle_df |> dplyr::filter(guid == !!guid)

      deploy_guid(
        guid,
        guid_bundles,
        metadata,
        content_perms,
        worker_connect,
        admin_user,
        content_env_vars,
        migrated_tag
      )
    },
    .progress = TRUE,
    .options = furrr_options(seed = NULL)
  )

  plan(sequential)
}
