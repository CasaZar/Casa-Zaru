param([string]$Db,[string]$Sql,[string]$OutCsv='')
# Lee una base SQLite con winsqlite3.dll (viene con Windows). Solo lectura: copia la base (+wal) a temp antes.
if(-not ('WinSqlite' -as [type])){
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Collections.Generic; using System.Text;
public static class WinSqlite {
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.StdCall)] static extern int sqlite3_open_v2(byte[] f, out IntPtr db, int flags, IntPtr vfs);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.StdCall)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int n, out IntPtr st, IntPtr tail);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.StdCall)] static extern int sqlite3_step(IntPtr st);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.StdCall)] static extern int sqlite3_column_count(IntPtr st);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.StdCall)] static extern IntPtr sqlite3_column_name(IntPtr st, int i);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.StdCall)] static extern IntPtr sqlite3_column_text(IntPtr st, int i);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.StdCall)] static extern int sqlite3_finalize(IntPtr st);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.StdCall)] static extern int sqlite3_close(IntPtr db);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.StdCall)] static extern IntPtr sqlite3_errmsg(IntPtr db);
  static string U(IntPtr p){ if(p==IntPtr.Zero) return null; int n=0; while(Marshal.ReadByte(p,n)!=0) n++; byte[] b=new byte[n]; Marshal.Copy(p,b,0,n); return Encoding.UTF8.GetString(b); }
  static byte[] Z(string s){ return Encoding.UTF8.GetBytes(s+"\0"); }
  public static List<string[]> Query(string file, string sql){
    IntPtr db; var r=new List<string[]>();
    if(sqlite3_open_v2(Z(file), out db, 1, IntPtr.Zero)!=0) throw new Exception("open: "+U(sqlite3_errmsg(db)));
    IntPtr st; if(sqlite3_prepare_v2(db, Z(sql), -1, out st, IntPtr.Zero)!=0){ string e=U(sqlite3_errmsg(db)); sqlite3_close(db); throw new Exception("sql: "+e); }
    int c=sqlite3_column_count(st); var h=new string[c]; for(int i=0;i<c;i++) h[i]=U(sqlite3_column_name(st,i)); r.Add(h);
    while(sqlite3_step(st)==100){ var row=new string[c]; for(int i=0;i<c;i++) row[i]=U(sqlite3_column_text(st,i)); r.Add(row); }
    sqlite3_finalize(st); sqlite3_close(db); return r;
  }
}
'@
}
$tmp=Join-Path $env:TEMP ('sqlro_'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $tmp | Out-Null
$base=Join-Path $tmp 'db'; Copy-Item $Db $base; foreach($x in '-wal','-shm'){ if(Test-Path "$Db$x"){ Copy-Item "$Db$x" "$base$x" } }
$rows=[WinSqlite]::Query($base,$Sql); $h=$rows[0]
$objs=for($i=1;$i -lt $rows.Count;$i++){ $o=[ordered]@{}; for($j=0;$j -lt $h.Count;$j++){ $o[$h[$j]]=$rows[$i][$j] }; [pscustomobject]$o }
if($OutCsv){ $objs | Export-Csv $OutCsv -NoTypeInformation -Encoding UTF8; "filas: $($objs.Count)" } else { $objs }
