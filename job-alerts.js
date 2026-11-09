(() => {
  const EMPLOYMENT = [
    ["full_time","دوام كامل"],["part_time","دوام جزئي"],["remote","عن بُعد"],
    ["contract","تعاقد"],["temporary","مؤقت"],["internship","تدريب"]
  ];
  const css = document.createElement("style");
  css.textContent = `
    #waziftiJobAlertsBtn{position:fixed;left:14px;bottom:18px;z-index:9000;border:0;border-radius:999px;padding:12px 17px;background:#087a4b;color:#fff;font:700 14px Tahoma;box-shadow:0 5px 18px #0002}
    #waziftiJobAlertsModal{position:fixed;inset:0;z-index:12000;background:#10251ccc;display:none;align-items:center;justify-content:center;padding:12px;box-sizing:border-box}
    #waziftiJobAlertsModal .wa-card{background:#fff;color:#183b2a;border-radius:18px;width:min(720px,100%);max-height:92vh;overflow:auto;padding:18px;box-sizing:border-box;font-family:Tahoma,Arial}
    #waziftiJobAlertsModal label{display:block;font-weight:700;margin:10px 0 6px}
    #waziftiJobAlertsModal input,#waziftiJobAlertsModal select{max-width:100%;box-sizing:border-box;padding:10px;border:1px solid #ccdcd2;border-radius:9px;font:inherit}
    #waziftiJobAlertsModal .wa-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:8px}
    #waziftiJobAlertsModal .wa-check{display:flex;gap:7px;align-items:center;background:#f4f8f5;border-radius:9px;padding:8px;font-size:13px}
    #waziftiJobAlertsModal .wa-options-toggle{width:100%;display:flex;justify-content:space-between;align-items:center;gap:10px;margin:14px 0 8px;padding:13px 14px;background:#edf6f0;border:1px solid #d5e8db;border-radius:11px;color:#145b39;font-weight:700;text-align:right}
    #waziftiJobAlertsModal .wa-options-panel{padding:4px 0 8px}
    #waziftiJobAlertsModal details.wa-group{border:1px solid #e0ebe4;border-radius:11px;margin:8px 0;background:#fff;overflow:hidden}
    #waziftiJobAlertsModal details.wa-group summary{cursor:pointer;list-style:none;padding:13px 14px;background:#f6faf7;color:#214d35;font-weight:700}
    #waziftiJobAlertsModal details.wa-group summary::-webkit-details-marker{display:none}
    #waziftiJobAlertsModal details.wa-group summary:after{content:"＋";float:left;color:#087a4b}
    #waziftiJobAlertsModal details.wa-group[open] summary:after{content:"−"}
    #waziftiJobAlertsModal .wa-group-body{padding:10px 12px}
    #waziftiJobAlertsModal button{font:700 14px Tahoma;cursor:pointer}
    #waziftiJobAlertsModal .wa-primary{background:#087a4b;color:#fff;border:0;border-radius:10px;padding:11px 16px}
    #waziftiJobAlertsModal .wa-secondary{background:#edf4ef;color:#24543c;border:1px solid #d5e4da;border-radius:10px;padding:10px 14px}
    #waziftiJobAlertsModal .wa-note{color:#66796d;font-size:12px;line-height:1.7}
    @media(max-width:520px){#waziftiJobAlertsBtn{bottom:12px;left:10px;padding:11px 13px}#waziftiJobAlertsModal .wa-card{padding:14px}}
  `;
  document.head.appendChild(css);
  const btn=document.createElement("button"); btn.id="waziftiJobAlertsBtn"; btn.type="button"; btn.textContent="تنبيهات الوظائف";
  btn.addEventListener("click",open); document.body.appendChild(btn);
  const modal=document.createElement("div"); modal.id="waziftiJobAlertsModal";
  modal.innerHTML=`<section class="wa-card" role="dialog" aria-modal="true" aria-labelledby="waTitle">
    <div style="display:flex;justify-content:space-between;align-items:center;gap:10px"><h2 id="waTitle" style="margin:0">تنبيهات الوظائف المناسبة لك</h2><button class="wa-secondary" id="waClose" type="button">إغلاق ✕</button></div>
    <p class="wa-note">اختر مجالاتك ومواقع العمل لتصلك الفرص الجديدة. يمكنك إيقاف التنبيهات في أي وقت.</p>
    <div id="waStatus" class="wa-note" role="status" aria-live="polite">جارٍ تحميل الإعدادات...</div>
    <label class="wa-check"><input id="waEnabled" type="checkbox"> تفعيل تنبيهات الوظائف</label>
    <button class="wa-options-toggle" id="waOptionsToggle" type="button" aria-expanded="false" aria-controls="waOptionsPanel"><span>خيارات التنبيه والتخصصات والمواقع</span><span id="waOptionsIcon" aria-hidden="true">＋</span></button>
    <div id="waOptionsPanel" class="wa-options-panel" hidden>
      <details class="wa-group"><summary>التصنيفات والتخصصات</summary><div class="wa-group-body">
        <label>التخصصات الرئيسية</label><div id="waCategories" class="wa-grid"></div>
        <label>التخصصات الفرعية</label><div id="waSpecialties" class="wa-grid"></div>
      </div></details>
      <details class="wa-group"><summary>موقع العمل</summary><div class="wa-group-body">
        <label for="waLocations">الولايات أو المدن (افصل بينها بفاصلة)</label><input id="waLocations" style="width:100%" placeholder="الخرطوم، أم درمان، الجزيرة">
      </div></details>
      <details class="wa-group"><summary>نوع العمل</summary><div class="wa-group-body"><div id="waEmployment" class="wa-grid"></div></div></details>
    </div>
    <label class="wa-check"><input id="waPush" type="checkbox"> أرسل إشعاراً فورياً على الهاتف أيضاً</label>
    <p class="wa-note">إشعارات الهاتف تحتاج السماح بها من المتصفح. ستظل إشعارات حالة طلبات التقديم منفصلة كما هي.</p>
    <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:14px"><button class="wa-primary" id="waSave" type="button">حفظ التفضيلات</button><button class="wa-secondary" id="waReload" type="button">تحديث التنبيهات</button></div>
    <hr style="border:0;border-top:1px solid #e2ebe5;margin:18px 0"><h3 style="margin:0 0 8px">الفرص التي وصلت إليك</h3><div id="waInbox" class="wa-note">—</div>
  </section>`;
  document.body.appendChild(modal);
  modal.addEventListener("click",e=>{if(e.target===modal)close();});
  modal.querySelector("#waClose").addEventListener("click",close);
  modal.querySelector("#waReload").addEventListener("click",loadInbox);
  modal.querySelector("#waSave").addEventListener("click",save);
  modal.querySelector("#waOptionsToggle").addEventListener("click",()=>{
    const panel=modal.querySelector("#waOptionsPanel");
    const opening=panel.hidden;
    panel.hidden=!opening;
    modal.querySelector("#waOptionsToggle").setAttribute("aria-expanded",String(opening));
    modal.querySelector("#waOptionsIcon").textContent=opening?"−":"＋";
  });
  function close(){modal.style.display="none";document.body.classList.remove("modal-open");}
  function status(t){modal.querySelector("#waStatus").textContent=t;}
  function checkedValues(root){return [...root.querySelectorAll("input:checked")].map(x=>x.value);}
  function checkbox(value,label){return '<label class="wa-check"><input type="checkbox" value="'+value+'"> '+label+'</label>';}
  async function open(){
    if(!window.currentAuthUser && typeof currentAuthUser==="undefined"){alert("يرجى تسجيل الدخول أولاً.");return;}
    if(typeof currentAuthUser==="undefined"||!currentAuthUser){alert("يرجى تسجيل الدخول أولاً.");return;}
    modal.style.display="flex";document.body.classList.add("modal-open");status("جارٍ تحميل إعدادات التنبيهات...");
    try{await loadTaxonomy();await loadPreferences();await loadInbox();status("يمكنك تعديل تفضيلاتك ثم حفظها.");}
    catch(e){status("تعذر تحميل الإعدادات: "+(e.message||"تحقق من الاتصال"));}
  }
  async function loadTaxonomy(){
    const {data:cats,error}=await supabaseClient.from("job_categories").select("id,name_ar,name_en").order("name_ar");
    if(error)throw error;
    const {data:specs,error:se}=await supabaseClient.from("job_specialties").select("id,category_id,name_ar,name_en").order("name_ar");
    if(se)throw se;
    const croot=modal.querySelector("#waCategories"),sroot=modal.querySelector("#waSpecialties");
    croot.innerHTML=(cats||[]).map(c=>checkbox(c.id,c.name_ar||c.name_en)).join("")||'<p class="wa-note">لا توجد تصنيفات متاحة حالياً.</p>';
    sroot.innerHTML=(specs||[]).map(s=>checkbox(s.id,s.name_ar||s.name_en)).join("")||'<p class="wa-note">لا توجد تخصصات فرعية متاحة حالياً.</p>';
    const eroot=modal.querySelector("#waEmployment");eroot.innerHTML=EMPLOYMENT.map(([v,l])=>checkbox(v,l)).join("");
    croot.querySelectorAll("input").forEach(x=>x.addEventListener("change",()=>{const ids=checkedValues(croot);sroot.querySelectorAll("label").forEach(l=>{const input=l.querySelector("input");const item=(specs||[]).find(s=>s.id===input?.value);l.style.opacity=(!ids.length||ids.includes(item?.category_id))?"1":".45";if(ids.length&&!ids.includes(item?.category_id))input.checked=false;});}));
  }
  async function loadPreferences(){
    const {data:p,error}=await supabaseClient.from("job_alert_preferences").select("id,is_enabled,push_enabled").eq("user_id",currentAuthUser.id).maybeSingle();
    if(error)throw error;
    modal.querySelector("#waEnabled").checked=!!p?.is_enabled;modal.querySelector("#waPush").checked=!!p?.push_enabled;
    if(!p)return;
    const [cats,specs,locs,types]=await Promise.all([
      supabaseClient.from("job_alert_preference_categories").select("category_id").eq("preference_id",p.id),
      supabaseClient.from("job_alert_preference_specialties").select("specialty_id").eq("preference_id",p.id),
      supabaseClient.from("job_alert_preference_locations").select("state").eq("preference_id",p.id),
      supabaseClient.from("job_alert_preference_employment_types").select("employment_type").eq("preference_id",p.id)
    ]);
    if(cats.error||specs.error||locs.error||types.error)throw new Error("تعذر تحميل بعض الفلاتر.");
    const set=(selector,values,key)=>{const v=new Set((values||[]).map(x=>x[key]));modal.querySelectorAll(selector+" input").forEach(x=>x.checked=v.has(x.value));};
    set("#waCategories",cats.data,"category_id");set("#waSpecialties",specs.data,"specialty_id");
    modal.querySelector("#waLocations").value=(locs.data||[]).map(x=>x.state).join("، ");
    const troot=modal.querySelector("#waEmployment");troot.innerHTML=EMPLOYMENT.map(([v,l])=>checkbox(v,l)).join("");
    set("#waEmployment",types.data,"employment_type");
  }
  async function loadInbox(){
    const box=modal.querySelector("#waInbox");
    const {data,error}=await supabaseClient.from("job_alert_notifications")
      .select("id,job_id,job_title_snapshot,job_location_snapshot,created_at,read_at")
      .eq("user_id",currentAuthUser.id).order("created_at",{ascending:false}).limit(25);
    if(error){box.textContent="تعذر تحميل تنبيهات الوظائف حالياً.";return;}
    if(!data?.length){box.textContent="لا توجد فرص مطابقة حتى الآن.";return;}
    box.innerHTML=data.map(n=>'<article style="padding:10px;border:1px solid #e1ece5;border-radius:10px;margin:7px 0;background:'+(n.read_at?'#fff':'#f2faf4')+'"><strong>'+esc(n.job_title_snapshot)+'</strong><div>'+esc(n.job_location_snapshot||"الموقع غير محدد")+'</div><small>'+new Date(n.created_at).toLocaleString("ar-SD")+'</small>'+(n.read_at?'':' <button class="wa-secondary" data-read="'+n.id+'" type="button">مقروء</button>')+'</article>').join("");
    box.querySelectorAll("[data-read]").forEach(b=>b.addEventListener("click",async()=>{const {error}=await supabaseClient.from("job_alert_notifications").update({read_at:new Date().toISOString()}).eq("id",b.dataset.read).eq("user_id",currentAuthUser.id);if(!error)loadInbox();}));
  }
  function esc(s){return String(s||"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));}
  async function ensurePush(){
    if(!("serviceWorker" in navigator)||!("PushManager" in window)||!("Notification" in window))throw new Error("هذا المتصفح لا يدعم إشعارات الهاتف.");
    const permission=Notification.permission==="default"?await Notification.requestPermission():Notification.permission;
    if(permission!=="granted")throw new Error("لم يتم السماح بالإشعارات من المتصفح.");
    const reg=await navigator.serviceWorker.register("/sw.js");await navigator.serviceWorker.ready;
    let sub=await reg.pushManager.getSubscription();
    if(!sub){
      if(typeof WAZIFTI_VAPID_PUBLIC_KEY==="undefined")throw new Error("مفتاح إشعارات الهاتف غير متاح.");
      const pad="=".repeat((4-WAZIFTI_VAPID_PUBLIC_KEY.length%4)%4);
      const raw=atob((WAZIFTI_VAPID_PUBLIC_KEY+pad).replace(/-/g,"+").replace(/_/g,"/"));
      sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:Uint8Array.from([...raw].map(c=>c.charCodeAt(0)))});
    }
    const {error}=await supabaseClient.from("push_subscriptions").upsert({user_id:currentAuthUser.id,endpoint:sub.endpoint,subscription:sub.toJSON(),updated_at:new Date().toISOString()},{onConflict:"endpoint"});
    if(error)throw error;
  }
  async function save(){
    const button=modal.querySelector("#waSave");button.disabled=true;status("جارٍ حفظ التفضيلات...");
    try{
      const push=modal.querySelector("#waPush").checked;
      if(push)await ensurePush();
      const locations=modal.querySelector("#waLocations").value.split(/[,،]/).map(x=>x.trim()).filter(Boolean);
      const args={
        p_is_enabled:modal.querySelector("#waEnabled").checked,
        p_delivery_mode:"instant",
        p_locations:locations,
        p_employment_types:checkedValues(modal.querySelector("#waEmployment")),
        p_daily_send_time:"08:00",
        p_categories:checkedValues(modal.querySelector("#waCategories")),
        p_specialties:checkedValues(modal.querySelector("#waSpecialties")),
        p_push_enabled:push
      };
      const {error}=await supabaseClient.rpc("save_job_alert_preferences",args);
      if(error)throw error;
      status("تم حفظ تفضيلات التنبيهات بنجاح.");await loadInbox();
    }catch(e){status("تعذر الحفظ: "+(e.message||"حدث خطأ"));}
    finally{button.disabled=false;}
  }
})();
