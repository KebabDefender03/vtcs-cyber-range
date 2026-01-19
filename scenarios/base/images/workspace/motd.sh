#!/bin/bash
# ============================================================================
# VTCS Cyber Range - Workspace Welcome Message
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║           VTCS CYBER RANGE - STUDENT WORKSPACE                     ║"
echo "╠════════════════════════════════════════════════════════════════════╣"
echo "║  Workspace: ${WORKSPACE_NAME:-Unknown}                                              ║"
echo "║  Team: ${TEAM:-Unknown}                                                       ║"
echo "╠════════════════════════════════════════════════════════════════════╣"
echo "║  RULES OF ENGAGEMENT:                                              ║"
echo "║  • Only attack designated targets on services_net                  ║"
echo "║  • Do not attempt to escape the container environment              ║"
echo "║  • Do not attack other team workspaces                             ║"
echo "║  • Document all activities in ~/notes/                             ║"
echo "╠════════════════════════════════════════════════════════════════════╣"
echo "║  USEFUL COMMANDS:                                                  ║"
echo "║  • nmap -sV <target>     - Service scan                            ║"
echo "║  • tcpdump -i eth0       - Capture traffic                         ║"
echo "║  • hydra                 - Password attacks                        ║"
echo "║  • sqlmap                - SQL injection testing                   ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
