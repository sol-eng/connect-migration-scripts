library(connectapi)
library(furrr)

connect_new <- connect(
  server = "http://localhost:3940",
  api_key = "up9mfb2b23NYWpcy14SPKy3t0MlABkcS"
)

admin_user <- "adminuser"
data_dir <- "/tmp/data"

bundle_files <- list.files(
  path = data_dir,
  pattern = "^bundle.*\\.tar\\.gz$",
  full.names = TRUE
)

relevant_content <- read.csv(file.path(data_dir, "relevant_content.csv"))
content_perms <- read.csv(file.path(data_dir, "relevant_content_perms.csv"))

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
  admin_user
) {
  has_multiple <- nrow(guid_bundles) > 1

  # Deploy in reverse order so the lowest-numbered bundle is deployed last (becomes active)
  if (has_multiple) {
    guid_bundles <- guid_bundles |> dplyr::arrange(dplyr::desc(file))
  }

  new_bundle_id <- NULL

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
        cat("  Successfully deployed:", new_bundle_id$content$guid, "\n")

        # Only poll if multiple bundles for this GUID
        if (has_multiple) {
          poll_task(new_bundle_id, wait = 2, callback = NULL)
          cat("  Deployment complete, proceeding to next bundle.\n")
        }
      },
      error = function(e) {
        cat("  Error deploying bundle:", e$message, "\n")
      },
      finally = {
        if (!is.null(bundle) && inherits(bundle, "connection")) {
          tryCatch(close(bundle), error = function(e) NULL)
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
    dplyr::filter(content_guid == guid, username != admin_user)

  for (i in seq_len(nrow(old_guid_perms))) {
    perm <- old_guid_perms[i, ]
    tryCatch(
      {
        target_guid <- user_guid_from_username(connect_new, perm$username)
        if (!is.na(target_guid)) {
          content_add_user(new_content, target_guid, role = perm$role)
          cat("  Added", perm$username, "as", perm$role, "\n")
        } else {
          cat("  User not found on target server:", perm$username, "\n")
        }
      },
      error = function(e) {
        cat(
          "  Error adding permission for",
          perm$username,
          ":",
          e$message,
          "\n"
        )
      }
    )
  }

  # Transfer ownership
  owner_row <- content_perms |>
    dplyr::filter(content_guid == guid, role == "owner", username != admin_user)

  if (nrow(owner_row) >= 1) {
    owner_username <- owner_row$username[1]
    tryCatch(
      {
        new_owner_guid <- user_guid_from_username(connect_new, owner_username)
        if (!is.na(new_owner_guid)) {
          content_update_owner(new_content, new_owner_guid)
          cat("  Ownership transferred to", owner_username, "\n")
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

  cat("\n")
  invisible(new_bundle_id)
}

# Process all GUIDs — each GUID is independent, fire-and-forget
# Multi-bundle GUIDs self-manage sequencing via poll_task
guids <- unique(bundle_df$guid)

for (guid in guids) {
  cat("Processing GUID:", guid, "\n")

  if (!any(relevant_content$guid == guid)) {
    cat("Warning: No metadata found for GUID:", guid, "\n\n")
    next
  }

  metadata <- relevant_content[relevant_content$guid == guid, ]
  guid_bundles <- bundle_df |> dplyr::filter(guid == !!guid)

  deploy_guid(
    guid,
    guid_bundles,
    metadata,
    content_perms,
    connect_new,
    admin_user
  )
}
