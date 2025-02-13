#!/usr/bin/env bash

# Sneakergit by WatskeBart

set -euo pipefail

usage() {
    cat << EOF
Usage: $0 <command> <repo-path> <usb-path> [--squash [message]]

Commands:
    create-bundle    Create a new bundle from repository
    apply-bundle    Apply an existing bundle to repository

Arguments:
    repo-path    Path to the git repository (absolute or relative)
    usb-path     Path to the USB drive or transfer directory (absolute or relative)
    --squash     Optional: Squash all commits into one before bundling
    message      Optional: Custom commit message for squashed commit (use quotes for messages with spaces)
EOF
    exit 1
}

get_repo_name() {
    local repo_path=$1
    cd "${repo_path}" || exit 1
    
    # Try to get the repository name from the remote origin
    local remote_url
    if remote_url=$(git config --get remote.origin.url 2>/dev/null); then
        basename "${remote_url}" .git
    else
        # Fallback to directory name
        basename "${repo_path}"
    fi
}

create_bundle() {
    local repo_path
    local usb_path
    local squash=${3:-false}
    local squash_message=${4:-"Squashed repository state"}
    repo_path=$(realpath "$1")
    usb_path=$(realpath "$2")
    local repo_name
    repo_name=$(get_repo_name "${repo_path}")
    local bundle_name="${repo_name}-bundle.git"
    
    cd "${repo_path}" || exit 1

    if [[ "${squash}" == true ]]; then
        echo "Creating squashed bundle with message: ${squash_message}"
        
        # Create a temporary branch for the squashed commits
        local temp_branch="temp-squash-$(date +%s)"
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        
        # Create a new orphan branch and commit everything
        git checkout --orphan "${temp_branch}"
        git add -A
        git commit -m "${squash_message}"
        
        # Create the bundle from the squashed branch
        git bundle create "${usb_path}/${bundle_name}" "${temp_branch}"
        
        # Clean up: return to original branch and delete temporary branch
        git checkout "${current_branch}"
        git branch -D "${temp_branch}"
    else
        local last_bundled=""
        [[ -f "${usb_path}/last-bundled-${repo_name}.txt" ]] && last_bundled=$(cat "${usb_path}/last-bundled-${repo_name}.txt")
        
        if [[ -z "${last_bundled}" ]]; then
            git bundle create "${usb_path}/${bundle_name}" --all
        else
            git bundle create "${usb_path}/${bundle_name}" "${last_bundled}..HEAD"
        fi
        
        git rev-parse HEAD > "${usb_path}/last-bundled-${repo_name}.txt"
    fi
    
    echo "Bundle created at ${usb_path}/${bundle_name}"
}

apply_bundle() {
    local repo_path
    local usb_path
    repo_path=$(realpath "$1")
    usb_path=$(realpath "$2")
    local repo_name
    repo_name=$(get_repo_name "${repo_path}")
    local bundle_name="${repo_name}-bundle.git"
    
    cd "${repo_path}" || exit 1
    
    if [[ ! -f "${usb_path}/${bundle_name}" ]]; then
        echo "No bundle found at ${usb_path}/${bundle_name}"
        exit 1
    fi
    
    if ! git bundle verify "${usb_path}/${bundle_name}"; then
        echo "Bundle verification failed"
        exit 1
    fi
    
    git remote add temp-bundle "${usb_path}/${bundle_name}" || {
        echo "Remote temp-bundle already exists, removing..."
        git remote remove temp-bundle
        git remote add temp-bundle "${usb_path}/${bundle_name}"
    }
    
    git fetch temp-bundle
    
    # Check if we're dealing with a squashed bundle
    if git rev-parse --verify temp-bundle/temp-squash-* >/dev/null 2>&1; then
        echo "Applying squashed bundle..."
        git merge --allow-unrelated-histories temp-bundle/temp-squash-*
    else
        git merge temp-bundle/master
    fi
    
    git remote remove temp-bundle
    
    echo "Bundle applied successfully"
}

main() {
    if [[ $# -lt 3 ]]; then
        usage
    fi

    local command=$1
    local repo_path=$2
    local usb_path=$3
    local squash=false
    local squash_message="Squashed repository state"

    # Check for squash flag and optional message
    if [[ "${4:-}" == "--squash" ]]; then
        squash=true
        # If there's a fifth argument, use it as the squash message
        if [[ -n "${5:-}" ]]; then
            squash_message="$5"
        fi
    fi

    # Check if paths exist
    if [[ ! -d "$repo_path" ]]; then
        echo "Error: Repository path does not exist: $repo_path"
        exit 1
    fi

    if [[ ! -d "$usb_path" ]]; then
        echo "Error: USB/transfer path does not exist: $usb_path"
        exit 1
    fi

    case "${command}" in
        create-bundle)
            create_bundle "${repo_path}" "${usb_path}" "${squash}" "${squash_message}"
            ;;
        apply-bundle)
            apply_bundle "${repo_path}" "${usb_path}"
            ;;
        *)
            echo "Unknown command: ${command}"
            usage
            ;;
    esac
}

main "$@"
