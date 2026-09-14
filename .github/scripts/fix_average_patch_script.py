from pathlib import Path

p = Path('.github/scripts/apply_average_formula.py')
text = p.read_text()

# League team has two legitimate configuration forwards with the same indentation.
old_league = """text = replace(
    text,
    '                  ratingColorDecayBase: _ratingColorDecayBase,\\n',
    '                  ratingColorDecayBase: _ratingColorDecayBase,\\n                  averageRatingColorDecayBase: _averageRatingColorDecayBase,\\n',
    count=1,
    label='dialog avatar average setting',
)
text = replace(
    text,
    '                  ratingColorDecayBase: _ratingColorDecayBase,\\n                    displayMode:',
    '                  ratingColorDecayBase: _ratingColorDecayBase,\\n                    averageRatingColorDecayBase: _averageRatingColorDecayBase,\\n                    displayMode:',
    count=1,
    label='formation average setting',
)
"""
new_league = """text = replace(
    text,
    '                  ratingColorDecayBase: _ratingColorDecayBase,\\n',
    '                  ratingColorDecayBase: _ratingColorDecayBase,\\n                  averageRatingColorDecayBase: _averageRatingColorDecayBase,\\n',
    count=2,
    label='league team average settings',
)
"""
if old_league in text:
    text = text.replace(old_league, new_league)
elif "label='league team average settings'" not in text:
    raise SystemExit('league team average patch block not found')

# formations.dart forwards the config to five PlayerAvatar instances. Replace all
# of them in one indentation-preserving regex instead of matching each layout.
start_marker = "text = replace(\n    text,\n    '                                  ratingColorDecayBase: widget.ratingColorDecayBase,\\n',"
end_marker = "p.write_text(text)\n\n\n# --- league_team_screen.dart ---"
start = text.find(start_marker)
end = text.find(end_marker)
if start == -1 or end == -1 or end <= start:
    raise SystemExit('formations average forwarding patch region not found')
replacement = """import re
average_forward_pattern = re.compile(
    r'(?m)^(\\s*)ratingColorDecayBase: widget\\.ratingColorDecayBase,$'
)
def _add_average_forward(match):
    indent = match.group(1)
    return (
        f'{indent}ratingColorDecayBase: widget.ratingColorDecayBase,\\n'
        f'{indent}averageRatingColorDecayBase: widget.averageRatingColorDecayBase,'
    )
text, average_forward_count = average_forward_pattern.subn(_add_average_forward, text)
if average_forward_count != 5:
    raise SystemExit(
        f'formation average settings: expected 5 occurrence(s), found {average_forward_count}'
    )
p.write_text(text)


# --- league_team_screen.dart ---"""
text = text[:start] + replacement + text[end + len(end_marker):]

p.write_text(text)
