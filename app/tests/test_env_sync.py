import os
from pathlib import Path

def test_env_files_in_sync():
    """Verify that .env and .env.example contain the same configuration keys."""
    
    # Get project root directory (2 levels up from tests folder)
    root_dir = Path(__file__).parent.parent.parent
    
    env_path = root_dir / '.env'
    env_example_path = root_dir / '.env.example'
    
    # Ensure both files exist
    assert env_path.exists(), ".env file not found"
    assert env_example_path.exists(), ".env.example file not found"
    
    # Read and parse both files
    def parse_env_file(file_path):
        with open(file_path) as f:
            # Filter out empty lines and comments, extract keys
            return {
                line.split('=')[0].strip() 
                for line in f.readlines() 
                if line.strip() and not line.startswith('#')
            }
    
    env_keys = parse_env_file(env_path)
    env_example_keys = parse_env_file(env_example_path)
    
    # Check for missing keys in both directions
    missing_in_env = env_example_keys - env_keys
    missing_in_example = env_keys - env_example_keys
    
    # Build error message if there are discrepancies
    error_msg = []
    if missing_in_env:
        error_msg.append(f"Keys missing in .env: {', '.join(missing_in_env)}")
    if missing_in_example:
        error_msg.append(f"Keys missing in .env.example: {', '.join(missing_in_example)}")
    
    assert not error_msg, "\n".join(error_msg) 