"""Run the real schema and migrations on an isolated native PostgreSQL server.

Usage: python supabase/tests/run_native.py --port 55439
Only pg_cron installation/scheduling is omitted; Auth/Storage have minimal stubs.
The database name must start with managerspiel_test_. Never targets production.
"""
import argparse,os,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--port',default='55439');p.add_argument('--database',default='managerspiel_test_repair');p.add_argument('--fixture-reimport',action='store_true');args=p.parse_args()
assert args.database.startswith('managerspiel_test_')
root=Path(__file__).resolve().parents[2]
psql=os.environ.get('PSQL',r'C:\Program Files\PostgreSQL\17\bin\psql.exe')
base=[psql,'-X','-h','127.0.0.1','-p',args.port,'-U','postgres','-v','ON_ERROR_STOP=1']
def sql(text,db=args.database):
    r=subprocess.run(base+['-d',db],input=text,encoding='utf-8',stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if r.returncode: print(r.stdout,r.stderr);raise SystemExit(r.returncode)
    return r.stdout
sql('CREATE DATABASE '+args.database+';', 'postgres')
sql((root/'supabase/tests/bootstrap_native.sql').read_text(encoding='utf-8'))
for f in sorted((root/'supabase/migrations').glob('*.sql')):
    if args.fixture_reimport and 'repair_matchday_integrity' in f.name:
        sql((root/'supabase/seed.sql').read_text(encoding='utf-8'))
        sql((root/'supabase/tests/fixture_reimport_before.sql').read_text(encoding='utf-8'))
    text=f.read_text(encoding='utf-8')
    if 'baseline' in f.name:
        text='\n'.join(l for l in text.splitlines() if not l.startswith('create extension if not exists pg_cron') and not l.startswith('select cron.schedule('))
    sql('BEGIN;\n'+text+'\nCOMMIT;'); print('PASS migration',f.name)
if args.fixture_reimport:
    sql((root/'supabase/tests/fixture_reimport_after.sql').read_text(encoding='utf-8'))
    print('PASS fixture deletion and reimport'); raise SystemExit(0)
sql((root/'supabase/seed.sql').read_text(encoding='utf-8'))
for f in sorted((root/'supabase/tests').glob('*_test.sql')):
    sql(f.read_text(encoding='utf-8')); print('PASS',f.name)
