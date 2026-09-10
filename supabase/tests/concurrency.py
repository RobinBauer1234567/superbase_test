"""Concurrency regressions; call with the isolated test DB created by run_native."""
import subprocess,sys,time
from pathlib import Path
psql=r'C:\Program Files\PostgreSQL\17\bin\psql.exe'
db=sys.argv[1]
port=sys.argv[2] if len(sys.argv) > 2 else '55439'
assert db.startswith('managerspiel_test_')
base=[psql,'-X','-qAt','-h','127.0.0.1','-p',port,'-U','postgres','-d',db,'-v','ON_ERROR_STOP=1']
def run(sql):
 r=subprocess.run(base,input=sql,encoding='utf-8',capture_output=True)
 if r.returncode: raise RuntimeError(r.stderr)
 return r.stdout.strip()
def race(a,b):
 p=subprocess.Popen(base,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
 p.stdin.write(a);p.stdin.close()
 time.sleep(.3)
 second=run(b)
 first=p.stdout.read();err=p.stderr.read();p.wait()
 if p.returncode: raise RuntimeError(err)
 return first,second
run("""
insert into auth.users(id,email) values ('00000000-0000-0000-0000-000000000011','concurrent@example.test');
insert into public.tournaments(id,name) values(17,'Concurrency');
insert into public.season(id,name,tournament_id) values(100,'Concurrency',17);
insert into public.leagues(id,name,admin_id,season_id) values(100,'Concurrency','00000000-0000-0000-0000-000000000011',100);
insert into public.league_members(league_id,user_id,budget) values(100,'00000000-0000-0000-0000-000000000011',1);
insert into public.spieltag(round,season_id,status) values(1,100,'nicht gestartet');
insert into public.sync_tasks(id,task_type,season_id,tournament_id) values('10000000-0000-0000-0000-000000000011','UPDATE_MATCH',100,17);
""")
auth="set local role authenticated; set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000011';"
call="select public.initialize_matchday_snapshot(100,'00000000-0000-0000-0000-000000000011',100,1);"
race('begin;'+auth+call+'select pg_sleep(1);commit;', 'begin;'+auth+call+'commit;')
assert run('select count(*) from public.user_matchday_points where league_id=100;')=='1'
call='select count(*) from public.get_next_sync_task(auth.uid());'
first,second=race('begin;'+auth+call+'select pg_sleep(1);commit;', 'begin;'+auth+call+'commit;')
assert first.strip().splitlines()[0]=='1' and second.strip()=='0',(first,second)
print('PASS concurrent snapshot initialization and SKIP LOCKED task claim')
