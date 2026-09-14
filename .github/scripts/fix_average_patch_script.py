from pathlib import Path

p = Path('.github/scripts/apply_average_formula.py')
text = p.read_text()
old = """text = replace(
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
new = """text = replace(
    text,
    '                  ratingColorDecayBase: _ratingColorDecayBase,\\n',
    '                  ratingColorDecayBase: _ratingColorDecayBase,\\n                  averageRatingColorDecayBase: _averageRatingColorDecayBase,\\n',
    count=2,
    label='league team average settings',
)
"""
if old not in text:
    raise SystemExit('average patch guard block not found')
p.write_text(text.replace(old, new))
