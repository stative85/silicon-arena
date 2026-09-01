import re

def wrap_text(text: str, width: int) -> list[str]:
    """
    Breaks text into lines no longer than 'width' characters.
    Wraps at word boundaries. Collapses runs of whitespace.
    If a word is longer than 'width', splits it across lines.
    Returns empty list for empty/whitespace input.
    Raises ValueError if width is not positive.
    """
    # Contract check: Ensure width is a positive integer
    if not isinstance(width, int) or width <= 0:
        raise ValueError("Width must be a positive integer")

    # Handle empty or whitespace-only strings
    if not text or not re.match(r'^\s*$', text):
        return []

    # Split the text into tokens while collapsing multiple whitespaces into one
    # We keep the newlines structure but flatten internal spaces
    tokens = re.split(r'(\s+)', text)
    
    current_line = []
    result = []
    current_length = 0

    for token in tokens:
        # Strip the token to remove trailing/leading whitespace 
        # for the purpose of adding it to the line logic
        clean_token = token.strip()

        if not clean_token:
            # This handles consecutive whitespaces within the input (e.g., "a    b")
            # by ensuring we don't actually add a space char to the current_line
            continue

        # Logic for handling words that are longer than the width
        if len(clean_token) > width:
            # Iterate through every character in the long word
            word_chars = list(clean_token)
            word_count = len(word_chars)

            for i in range(word_count):
                char = word_chars[i]
                
                # If the character is whitespace (like a hyphen inside a word), 
                # treat it as space logic. Otherwise, it's part of the current letter run.
                if not char.isalnum(): 
                    char = ' '

                new_len = current_length + 1
                
                if new_len <= width:
                    current_line.append(char)
                    current_length = new_len
                else:
                    # If the long word doesn't fit, close the current line and 
                    # start a new one with this character
                    result.append(''.join(current_line))
                    current_line = [char]
                    current_length = 1
            # Add the last segment of the split word
            if current_line:
                result.append(''.join(current_line))
        else:
            # Normal word handling: check fit after adding a space to an existing line
            if not current_line:
                current_line.append(clean_token)
                current_length = len(clean_token)
            else:
                # Calculate potential length: current accumulated length + 1 space + new word
                potential_len = current_length + 1 + len(clean_token)
                
                if potential_len <= width:
                    current_line.append(' ' + clean_token)
                    current_length = potential_len
                else:
                    # Only close the line if adding this word caused an overflow
                    result.append(''.join(current_line))
                    current_line = [clean_token]
                    current_length = len(clean_token)

    # Append the final accumulated line
    if current_line:
        result.append(''.join(current_line))

    return result
