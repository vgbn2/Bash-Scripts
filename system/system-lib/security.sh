# Cybersecurity, reconnaissance, and pentest lab integration.

show_security_summary() {
    delegate_tool "security/security" audit host
}

run_security() {
    if [ -z "${action:-}" ]; then
        enter_section security
    else
        delegate_tool "security/security" "$action" "${arg3:-}" "${arg4:-}"
    fi
}
