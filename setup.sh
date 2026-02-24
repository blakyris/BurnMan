#!/bin/bash

# ============================================================
#  setup.sh — Configure et ouvre le projet BurnMan dans Xcode
# ============================================================

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error()   { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }

echo ""
echo "🔥 BurnMan — Setup"
echo "────────────────────────────────"

# --- Vérifier les prérequis ---

info "Vérification des prérequis..."

# Xcode
if ! command -v xcodebuild &> /dev/null; then
    error "Xcode n'est pas installé. Installe-le depuis l'App Store."
fi
success "Xcode trouvé"

# Homebrew
if ! command -v brew &> /dev/null; then
    error "Homebrew n'est pas installé. Installe-le : https://brew.sh"
fi
success "Homebrew trouvé"

# cdrdao
if ! command -v cdrdao &> /dev/null; then
    info "Installation de cdrdao..."
    brew install cdrdao
fi
success "cdrdao trouvé : $(which cdrdao)"

# XcodeGen
if ! command -v xcodegen &> /dev/null; then
    info "Installation de XcodeGen..."
    brew install xcodegen
fi
success "XcodeGen trouvé"

# --- Générer le projet Xcode ---

info "Génération du projet Xcode..."
cd "$(dirname "$0")"
xcodegen generate

if [ ! -d "BurnMan.xcodeproj" ]; then
    error "Le projet n'a pas été généré."
fi
success "BurnMan.xcodeproj généré"

# --- Ouvrir dans Xcode ---

echo ""
info "Ouverture dans Xcode..."
open BurnMan.xcodeproj

echo ""
echo "────────────────────────────────"
success "Setup terminé !"
echo ""
echo "  Prochaines étapes :"
echo "  1. Sélectionner le scheme BurnMan"
echo "  2. Choisir 'My Mac' comme destination"
echo "  3. ⌘R pour lancer"
echo ""
echo "  Note : Pour le mode raw, le helper sera"
echo "  installé automatiquement (demande du mdp admin)"
echo ""
