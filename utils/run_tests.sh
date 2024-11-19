#!/bin/bash
set -e  # Exit on any error

# Create docs directory if it doesn't exist
DOCS_DIR="docs"
mkdir -p $DOCS_DIR

echo "🧪 Running tests with coverage..."

# Clean up previous coverage data and reports
echo "🧹 Cleaning up previous coverage data..."
rm -rf $DOCS_DIR/coverage_html $DOCS_DIR/coverage.xml $DOCS_DIR/coverage_badge.svg || true
rm -f .coverage  # Remove any stray .coverage file

# Set coverage RC file location and output directories
export COVERAGE_FILE="$DOCS_DIR/.coverage"

# Run tests with coverage and show full output
echo "📊 Running pytest with coverage..."
PYTHONPATH=. timeout 30 pytest --cov=app \
      --cov-report=term-missing \
      --cov-report=html:$DOCS_DIR/coverage_html \
      --cov-report=xml:$DOCS_DIR/coverage.xml \
      -v \
      --no-cov-on-fail \
      --maxfail=999 \
      --tb=short \
      --show-capture=no \
      --capture=tee-sys \
      --log-cli-level=INFO \
      -o console_output_style=progress \
      --disable-warnings

# Store the exit code
PYTEST_EXIT_CODE=$?

# Check if pytest timed out or failed
if [ $PYTEST_EXIT_CODE -eq 124 ]; then
    echo "❌ Tests timed out after 30 seconds"
    exit 1
elif [ $PYTEST_EXIT_CODE -ne 0 ]; then
    echo "❌ Tests failed with exit code $PYTEST_EXIT_CODE"
    exit $PYTEST_EXIT_CODE
fi

echo ""
echo "📈 Coverage Summary:"
echo "----------------------------------------"
coverage report --rcfile=pyproject.toml --sort=Cover

echo ""
echo "📊 Coverage Details (files with missing lines):"
echo "----------------------------------------"
coverage report --rcfile=pyproject.toml --sort=Cover --skip-covered --show-missing

# Get the coverage percentage
COVERAGE=$(coverage report --rcfile=pyproject.toml | grep TOTAL | awk '{print $4}' | sed 's/%//')
echo ""
echo "📊 Total Coverage: $COVERAGE%"

# Generate coverage badge
echo "🎨 Generating coverage badge..."
cd $DOCS_DIR && coverage-badge -o coverage_badge.svg && cd ..

echo ""
echo "✨ Test run complete!"
echo "📝 Reports generated in $DOCS_DIR:"
echo "  - Terminal report (above)"
echo "  - HTML report: coverage_html/index.html"
echo "  - XML report: coverage.xml"
echo "  - Coverage badge: coverage_badge.svg"
echo ""
echo "🌐 To view the HTML report, open:"
echo "file://$(pwd)/$DOCS_DIR/coverage_html/index.html"

# Check if coverage is below threshold
THRESHOLD=80
if (( $(echo "$COVERAGE < $THRESHOLD" | bc -l) )); then
    echo "⚠️  Warning: Coverage ($COVERAGE%) is below threshold ($THRESHOLD%)"
fi

# Clean up any stray coverage files
rm -f .coverage

# Show test failures in detail if any exist
if [ -f ".pytest_cache/v/cache/lastfailed" ]; then
    echo ""
    echo "❌ Failed Tests:"
    echo "----------------------------------------"
    cat .pytest_cache/v/cache/lastfailed
fi