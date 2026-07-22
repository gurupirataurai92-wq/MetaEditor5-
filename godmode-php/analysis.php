<?php
require_once __DIR__ . '/includes/functions.php';
$pageTitle = 'Financial Analysis';
require __DIR__ . '/includes/header.php';
?>
<div class="view-head">
  <div><h1>Financial Analysis Toolkit</h1>
    <div class="sub">Ratios, break-even, NPV, and business valuation — instant answers in client meetings.</div></div>
</div>

<div class="grid grid-3">
  <div class="card">
    <h3>Ratio Analysis</h3>
    <form id="f-ratios">
      <div class="form-row">
        <div><label>Current assets</label><input name="ca" type="number" step="any" value="0"></div>
        <div><label>Current liabilities</label><input name="cl" type="number" step="any" value="0"></div>
        <div><label>Inventory</label><input name="inv" type="number" step="any" value="0"></div>
        <div><label>Total debt</label><input name="debt" type="number" step="any" value="0"></div>
        <div><label>Total equity</label><input name="eq" type="number" step="any" value="0"></div>
        <div><label>Total assets</label><input name="ta" type="number" step="any" value="0"></div>
        <div><label>Revenue</label><input name="rev" type="number" step="any" value="0"></div>
        <div><label>Net income</label><input name="ni" type="number" step="any" value="0"></div>
      </div>
      <button class="btn btn-primary mt" type="submit">Compute</button>
    </form>
    <div id="out-ratios" class="mt"></div>
  </div>
  <div class="card">
    <h3>Break-even</h3>
    <form id="f-be">
      <label>Fixed costs / period</label><input name="fc" type="number" step="any" value="0">
      <label>Price per unit</label><input name="p" type="number" step="any" value="0">
      <label>Variable cost per unit</label><input name="vc" type="number" step="any" value="0">
      <button class="btn btn-primary mt" type="submit">Compute</button>
    </form>
    <div id="out-be" class="mt"></div>
  </div>
  <div class="card">
    <h3>NPV &amp; Payback</h3>
    <form id="f-npv">
      <label>Discount rate % / period</label><input name="rate" type="number" step="any" value="10">
      <label>Initial investment (positive number)</label><input name="inv" type="number" step="any" value="0">
      <label>Cash flows (comma separated, per period)</label>
      <input name="cf" placeholder="e.g. 500, 700, 900, 900">
      <button class="btn btn-primary mt" type="submit">Compute</button>
    </form>
    <div id="out-npv" class="mt"></div>
  </div>
  <div class="card">
    <h3>Business Valuation (DCF)</h3>
    <form id="f-dcf">
      <div class="form-row">
        <div><label>Free cash flow / year</label><input name="fcf" type="number" step="any" value="0"></div>
        <div><label>Growth % (yrs 1–5)</label><input name="g" type="number" step="any" value="8"></div>
        <div><label>Terminal growth %</label><input name="tg" type="number" step="any" value="2.5"></div>
        <div><label>Discount rate %</label><input name="r" type="number" step="any" value="18"></div>
      </div>
      <button class="btn btn-primary mt" type="submit">Value the business</button>
    </form>
    <div id="out-dcf" class="mt"></div>
  </div>
  <div class="card">
    <h3>Quick Multiples Valuation</h3>
    <form id="f-mult">
      <div class="form-row">
        <div><label>Annual EBITDA</label><input name="ebitda" type="number" step="any" value="0"></div>
        <div><label>Sector multiple</label><input name="mult" type="number" step="any" value="4"></div>
      </div>
      <button class="btn btn-primary mt" type="submit">Compute range</button>
    </form>
    <div id="out-mult" class="mt"></div>
  </div>
</div>

<script>
const CUR = <?= json_encode(currency_code()) ?>;
const SYM = {USD:'$',EUR:'€',GBP:'£',INR:'₹',BRL:'R$',MXN:'MX$',KES:'KSh ',NGN:'₦',ZAR:'R',GHS:'GH₵',UGX:'USh ',TZS:'TSh ',RWF:'FRw ',ZMW:'K',PHP:'₱',IDR:'Rp '};
function money(n){var s=SYM[CUR]||(CUR+' ');var v=Number(n)||0;return (v<0?'-':'')+s+Math.abs(v).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2});}
function num(n){return (Number(n)||0).toLocaleString(undefined,{maximumFractionDigits:2});}
function line(l,v,note){return '<div class="report-line"><span>'+l+(note?' <span class="muted">('+note+')</span>':'')+'</span><span class="amt">'+v+'</span></div>';}
function gv(fd,k){return Number(fd.get(k))||0;}

document.getElementById('f-ratios').addEventListener('submit',function(e){e.preventDefault();var fd=new FormData(e.target);
  var ca=gv(fd,'ca'),cl=gv(fd,'cl'),inv=gv(fd,'inv'),debt=gv(fd,'debt'),eq=gv(fd,'eq'),ta=gv(fd,'ta'),rev=gv(fd,'rev'),ni=gv(fd,'ni');
  var r=function(a,b){return b?num(a/b):'—';};var pct=function(a,b){return b?num(a/b*100)+'%':'—';};
  document.getElementById('out-ratios').innerHTML=line('Current ratio',r(ca,cl),'≥ 1.5 healthy')+line('Quick ratio',r(ca-inv,cl),'≥ 1.0 healthy')+
    line('Debt-to-equity',r(debt,eq),'< 2.0 typical')+line('Net margin',pct(ni,rev))+line('Return on assets',pct(ni,ta))+line('Return on equity',pct(ni,eq));});

document.getElementById('f-be').addEventListener('submit',function(e){e.preventDefault();var fd=new FormData(e.target);
  var fc=gv(fd,'fc'),p=gv(fd,'p'),vc=gv(fd,'vc'),cm=p-vc;
  document.getElementById('out-be').innerHTML=cm>0?line('Contribution margin / unit',money(cm))+line('Break-even units',num(Math.ceil(fc/cm)))+
    line('Break-even revenue',money(Math.ceil(fc/cm)*p))+line('CM ratio',num(cm/p*100)+'%'):'<div class="muted">Price must exceed variable cost per unit.</div>';});

document.getElementById('f-npv').addEventListener('submit',function(e){e.preventDefault();var fd=new FormData(e.target);
  var rate=gv(fd,'rate')/100,inv=gv(fd,'inv');
  var cfs=String(fd.get('cf')||'').split(',').map(function(s){return s.trim();}).filter(Boolean).map(Number).filter(function(x){return !isNaN(x);});
  var npv=-inv,cum=-inv,payback=null;
  cfs.forEach(function(cf,i){npv+=cf/Math.pow(1+rate,i+1);var prev=cum;cum+=cf;if(payback===null&&cum>=0&&cf>0)payback=i+(prev<0?(-prev/cf):0);});
  document.getElementById('out-npv').innerHTML=line('NPV',money(npv))+line('Verdict',npv>0?'<span class="pos">Accept — value creating</span>':'<span class="neg">Reject — value destroying</span>')+
    line('Simple payback',payback!==null?num(payback)+' periods':'not recovered');});

document.getElementById('f-dcf').addEventListener('submit',function(e){e.preventDefault();var fd=new FormData(e.target);
  var fcf=gv(fd,'fcf'),g=gv(fd,'g')/100,tg=gv(fd,'tg')/100,r=gv(fd,'r')/100;
  if(r<=tg){document.getElementById('out-dcf').innerHTML='<div class="neg">Discount rate must exceed terminal growth.</div>';return;}
  var ev=0,cf=fcf;for(var t=1;t<=5;t++){cf=cf*(1+g);ev+=cf/Math.pow(1+r,t);}
  var tv=(cf*(1+tg))/(r-tg)/Math.pow(1+r,5);
  document.getElementById('out-dcf').innerHTML=line('PV of 5-year cash flows',money(ev))+line('PV of terminal value',money(tv))+
    line('<strong>Enterprise value</strong>','<strong>'+money(ev+tv)+'</strong>')+line('Conservative (−25%)',money((ev+tv)*0.75),'negotiation floor');});

document.getElementById('f-mult').addEventListener('submit',function(e){e.preventDefault();var fd=new FormData(e.target);
  var eb=gv(fd,'ebitda'),m=gv(fd,'mult');
  document.getElementById('out-mult').innerHTML=line('Low (×'+num(Math.max(1,m-1))+')',money(eb*Math.max(1,m-1)))+
    line('Mid (×'+num(m)+')',money(eb*m))+line('High (×'+num(m+1)+')',money(eb*(m+1)));});
</script>

<?php require __DIR__ . '/includes/footer.php'; ?>
