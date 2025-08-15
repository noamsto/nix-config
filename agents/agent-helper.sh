#!/usr/bin/env bash
# Agent Helper - CLI tool for interacting with NixOS configuration agents

set -euo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DEFINITIONS="$AGENT_DIR/*.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to list available agents
list_agents() {
    print_color "$CYAN" "Available NixOS Configuration Agents:"
    echo ""
    for agent_file in $AGENT_DIR/*.yaml; do
        if [[ -f "$agent_file" && "$agent_file" != *"coordination.yaml" ]]; then
            agent_name=$(basename "$agent_file" .yaml)
            description=$(grep "^description:" "$agent_file" | cut -d':' -f2- | xargs)
            print_color "$GREEN" "  • $agent_name"
            echo "    $description"
        fi
    done
    echo ""
}

# Function to show agent details
show_agent() {
    local agent_name=$1
    local agent_file="$AGENT_DIR/${agent_name}.yaml"
    
    if [[ ! -f "$agent_file" ]]; then
        print_color "$RED" "Error: Agent '$agent_name' not found"
        return 1
    fi
    
    print_color "$CYAN" "=== Agent: $agent_name ==="
    echo ""
    
    # Extract and display key sections
    print_color "$YELLOW" "Description:"
    grep "^description:" "$agent_file" | cut -d':' -f2- | xargs
    echo ""
    
    print_color "$YELLOW" "Primary Expertise:"
    sed -n '/^  primary:/,/^  [a-z]/p' "$agent_file" | grep "    -" | sed 's/    - /  • /'
    echo ""
    
    print_color "$YELLOW" "File Patterns:"
    grep "^  - " "$agent_file" | head -10 | sed 's/  - /  • /'
    echo ""
}

# Function to suggest agent for a task
suggest_agent() {
    local task_description="$1"
    local best_match=""
    local best_score=0
    
    print_color "$CYAN" "Analyzing task: $task_description"
    echo ""
    
    for agent_file in $AGENT_DIR/*.yaml; do
        if [[ -f "$agent_file" && "$agent_file" != *"coordination.yaml" ]]; then
            agent_name=$(basename "$agent_file" .yaml)
            
            # Count keyword matches
            score=0
            while IFS= read -r keyword; do
                if [[ "${task_description,,}" == *"${keyword,,}"* ]]; then
                    ((score++))
                fi
            done < <(grep "^  - " "$agent_file" | head -20 | sed 's/^  - //')
            
            if [[ $score -gt $best_score ]]; then
                best_score=$score
                best_match=$agent_name
            fi
            
            if [[ $score -gt 0 ]]; then
                print_color "$GREEN" "  $agent_name: relevance score $score"
            fi
        fi
    done
    
    echo ""
    if [[ -n "$best_match" ]]; then
        print_color "$YELLOW" "Recommended agent: $best_match"
        show_agent "$best_match" | head -15
    else
        print_color "$YELLOW" "No specific agent recommended. Consider using the general coordinator."
    fi
}

# Function to run agent command
run_command() {
    local agent_name=$1
    local command_name=$2
    shift 2
    local args=("$@")
    
    local agent_file="$AGENT_DIR/${agent_name}.yaml"
    
    if [[ ! -f "$agent_file" ]]; then
        print_color "$RED" "Error: Agent '$agent_name' not found"
        return 1
    fi
    
    print_color "$CYAN" "Executing $command_name with $agent_name agent..."
    
    # Extract and execute command template
    # Note: This is a simplified version - real implementation would parse YAML properly
    case "$agent_name" in
        nixos-system)
            case "$command_name" in
                rebuild)
                    echo "sudo nixos-rebuild ${args[0]:-switch} --flake .#${args[1]:-$(hostname)}"
                    ;;
                check)
                    nix flake check
                    ;;
                *)
                    print_color "$RED" "Unknown command: $command_name"
                    ;;
            esac
            ;;
        flake-mgr)
            case "$command_name" in
                update)
                    nix flake update ${args[0]:-}
                    ;;
                check)
                    nix flake check
                    ;;
                show)
                    nix flake show
                    ;;
                *)
                    print_color "$RED" "Unknown command: $command_name"
                    ;;
            esac
            ;;
        *)
            print_color "$YELLOW" "Command execution not yet implemented for $agent_name"
            ;;
    esac
}

# Function to show coordination workflow
show_workflow() {
    local workflow_name=$1
    local coord_file="$AGENT_DIR/coordination.yaml"
    
    if [[ ! -f "$coord_file" ]]; then
        print_color "$RED" "Error: Coordination file not found"
        return 1
    fi
    
    print_color "$CYAN" "=== Workflow: $workflow_name ==="
    echo ""
    
    # This is simplified - real implementation would parse YAML
    case "$workflow_name" in
        update)
            print_color "$YELLOW" "System Update Workflow:"
            echo "  1. flake-mgr: Update inputs and validate"
            echo "  2. pkg-coord: Resolve package changes"
            echo "  3. nixos-system: Rebuild system configuration"
            echo "  4. dev-env: Update development tools"
            echo "  5. hyprland-desktop: Reload desktop environment"
            ;;
        deploy-rpi)
            print_color "$YELLOW" "Raspberry Pi Deployment Workflow:"
            echo "  1. rpi-deploy: Prepare deployment strategy"
            echo "  2. nixos-system: Verify system configuration"
            echo "  3. pkg-coord: Check architecture compatibility"
            echo "  4. flake-mgr: Ensure inputs available"
            echo "  5. rpi-deploy: Execute deployment"
            ;;
        *)
            print_color "$RED" "Unknown workflow: $workflow_name"
            ;;
    esac
}

# Main command handler
main() {
    case "${1:-help}" in
        list)
            list_agents
            ;;
        show)
            if [[ -z "${2:-}" ]]; then
                print_color "$RED" "Usage: $0 show <agent-name>"
                exit 1
            fi
            show_agent "$2"
            ;;
        suggest)
            if [[ -z "${2:-}" ]]; then
                print_color "$RED" "Usage: $0 suggest <task-description>"
                exit 1
            fi
            shift
            suggest_agent "$*"
            ;;
        run)
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                print_color "$RED" "Usage: $0 run <agent-name> <command> [args...]"
                exit 1
            fi
            agent=$2
            command=$3
            shift 3
            run_command "$agent" "$command" "$@"
            ;;
        workflow)
            if [[ -z "${2:-}" ]]; then
                print_color "$RED" "Usage: $0 workflow <workflow-name>"
                exit 1
            fi
            show_workflow "$2"
            ;;
        help|*)
            print_color "$CYAN" "NixOS Configuration Agent Helper"
            echo ""
            print_color "$YELLOW" "Usage:"
            echo "  $0 list                          - List all available agents"
            echo "  $0 show <agent>                  - Show details for specific agent"
            echo "  $0 suggest <task>                - Suggest best agent for a task"
            echo "  $0 run <agent> <command> [args]  - Run agent-specific command"
            echo "  $0 workflow <name>               - Show coordination workflow"
            echo "  $0 help                          - Show this help message"
            echo ""
            print_color "$YELLOW" "Examples:"
            echo "  $0 suggest 'update hyprland configuration'"
            echo "  $0 show hyprland-desktop"
            echo "  $0 run nixos-system rebuild switch thinkpad-p14s"
            echo "  $0 workflow update"
            ;;
    esac
}

main "$@"