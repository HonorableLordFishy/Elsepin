/* Development-only browser regression checks. No browser dependency is exported. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const qaRequire = process.env.ELSEPIN_QA_MODULES
  ? createRequire(path.resolve(process.env.ELSEPIN_QA_MODULES, '..', 'package.json')) : require;
const { chromium, webkit } = qaRequire('playwright');
const { AxeBuilder } = qaRequire('@axe-core/playwright');
const base = process.env.ELSEPIN_PREVIEW_URL || 'http://127.0.0.1:8770/';
const output = path.resolve(process.env.ELSEPIN_QA_OUTPUT || '.build/website-qa/verified');
const report = { checks: [], accessibility: [], requests: [], errors: [], metrics: {} };
let activeBrowser;
fs.mkdirSync(output, { recursive:true });

async function check(name, work) {
  try { await work(); report.checks.push({name,pass:true}); console.log('PASS ' + name); }
  catch (error) { report.checks.push({name,pass:false,error:error.stack}); console.error('FAIL ' + name + ': ' + error.message); }
}
async function settled(page) {
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all(document.getAnimations().map(animation => animation.finished.catch(() => {})));
  });
}
async function layout(page) {
  const problems = await page.evaluate(() => {
    const elements = [...document.querySelectorAll('body *')].filter(element => {
      if (!(element instanceof HTMLElement) || element.matches('.skip,.sr-only') || element.closest('[aria-hidden="true"]')) return false;
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && (rect.right > innerWidth + 1 || rect.left < -1);
    });
    return { viewport:innerWidth, width:document.documentElement.scrollWidth,
      elements:elements.slice(0,10).map(element => element.tagName + '.' + element.className) };
  });
  assert(problems.width <= problems.viewport + 1 && !problems.elements.length, JSON.stringify(problems));
}
async function accessibility(page, name, scope) {
  let scan = new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21aa']);
  if (scope) scan = scan.include(scope);
  const result = await scan.analyze();
  const violations = result.violations.map(item => ({id:item.id,impact:item.impact,nodes:item.nodes.map(node => ({target:node.target,summary:node.failureSummary}))}));
  report.accessibility.push({name,violations});
  assert.equal(violations.length,0,JSON.stringify(violations));
}
async function newPage(browser, options={}) {
  const context = await browser.newContext(options);
  const page = await context.newPage();
  page.on('pageerror', error => report.errors.push({url:page.url(),message:error.message}));
  page.on('response', response => {
    if (response.status() >= 400) report.errors.push({url:response.url(),status:response.status()});
  });
  page.on('request', request => report.requests.push(request.url()));
  return {context,page};
}
async function go(page, route='index.html') {
  const response = await page.goto(new URL(route,base).href,{waitUntil:'networkidle'});
  assert.equal(response.status(),200); await settled(page);
}
async function capture(page, name, selector) {
  if (selector) await page.locator(selector).screenshot({path:path.join(output,name+'.png')});
  else await page.screenshot({path:path.join(output,name+'.png'),fullPage:true});
}

(async()=>{
  for (const engine of ['chromium','webkit']) {
    const type = engine === 'chromium' ? chromium : webkit;
    activeBrowser = await type.launch({headless:true,...(engine === 'chromium' && process.env.CHROMIUM_EXECUTABLE ? {executablePath:process.env.CHROMIUM_EXECUTABLE} : {})});
    const {context,page} = await newPage(activeBrowser,{viewport:{width:1440,height:1000}});
    await go(page);
    await check(engine + ': skip link transfers keyboard focus to main',async()=>{
      await page.keyboard.press('Tab');
      assert(await page.locator('.skip').evaluate(node=>node===document.activeElement));
      await page.keyboard.press('Enter');
      assert.equal(await page.evaluate(()=>document.activeElement.id),'main');
    });
    await check(engine + ': initial preview matches native defaults', async()=>{
      assert.equal(await page.getAttribute('body','data-preview-ready'),'true');
      assert.equal(await page.locator('[data-theme][aria-pressed=true]').getAttribute('data-theme'),'bloom');
      assert.equal(await page.locator('[data-icon][aria-pressed=true]').count(),1);
      assert(await page.locator('#mode').isDisabled());
    });
    await check(engine + ': preview dialog opens from every entry, restores state and keyboard focus',async()=>{
      const triggers=page.locator('[data-open-preview]');
      for(let i=0;i<await triggers.count();i++) {
        const trigger=triggers.nth(i); await trigger.click(); await settled(page);
        assert(await page.locator('#preview-dialog').isVisible());
        assert.equal(await page.locator('#dialog-body #studio-body').count(),1);
        assert.equal(await page.locator('#phone').count(),1);
        await page.locator('[data-theme=ion]').click();
        await page.locator('[data-place=gardens]').click();
        assert.equal(await page.locator('#tray-title').innerText(),'Garden Gate');
        await page.locator('#demo-teleport').click();
        assert.equal(await page.locator('#phone').getAttribute('data-demo-active'),'true');
        await page.keyboard.press('Escape');
        await page.waitForFunction(()=>document.querySelector('#studio-slot #studio-body'));
        assert(await trigger.evaluate(node=>node===document.activeElement));
        assert.equal(await page.locator('#theme-name').innerText(),'Ion');
        await page.locator('#reset-preview').click();
      }
      await page.locator('.hero [data-open-preview]').focus(); await page.keyboard.press('Enter');
      await accessibility(page,engine+'-dialog');
      await capture(page,engine+'-dialog','#preview-dialog');
      await page.locator('#close-preview').click();
      await page.waitForFunction(()=>document.querySelector('#studio-slot #studio-body'));
    });
    await check(engine + ': scroll chapters change the map and status without trapping scroll',async()=>{
      const transforms=[];
      for(let i=0;i<3;i++) {
        await page.locator(`[data-story="${i}"]`).evaluate(node=>window.scrollTo({top:node.getBoundingClientRect().top+scrollY,behavior:'instant'}));
        await page.waitForFunction(i=>document.querySelector('#experience').dataset.step===String(i),i);
        transforms.push(await page.locator('.story-map-wrap').evaluate(node=>getComputedStyle(node).transform));
        await page.screenshot({path:path.join(output,engine+'-story-'+i+'.png')});
      }
      assert.equal(new Set(transforms).size,3);
      await page.mouse.wheel(0,1200); await page.waitForTimeout(200);
      assert(await page.locator('#studio').evaluate(node=>node.getBoundingClientRect().top<innerHeight));
    });
    await check(engine + ': every theme, surface, and visible state',async()=>{
      for (const id of await page.locator('[data-theme]').evaluateAll(nodes=>nodes.map(node=>node.dataset.theme))) {
        await page.locator(`[data-theme=${id}]`).click();
        for (const surface of ['solid','glass']) {
          await page.locator('#surface').selectOption(surface); await settled(page);
          assert.equal(await page.locator('#phone').evaluate(node=>node.classList.contains('glass')),surface === 'glass');
          const palette = await page.evaluate(id=>{
            const theme=window.ELSEPIN_CATALOG.themes.find(item=>item.id===id);
            return {actual:document.querySelector('#phone').style.getPropertyValue('--accent'),expected:theme[theme.mode==='dark'?'dark':'light'].accent};
          },id);
          assert.equal(palette.actual,palette.expected);
          if (engine === 'chromium') await accessibility(page,`${id}-${surface}`,'#phone');
        }
      }
    });
    await check(engine + ': Glacier follows device setting and changes live',async()=>{
      await page.locator('[data-theme=glacier]').click(); assert(await page.locator('#mode').isEnabled());
      for(const mode of ['dark','light']) {
        await page.locator('#mode').selectOption(mode); await settled(page);
        assert.equal(await page.locator('#phone').evaluate(node=>node.style.colorScheme),mode);
      }
      await page.locator('#mode').selectOption('system');
      await page.emulateMedia({colorScheme:'dark'}); await page.waitForFunction(()=>document.querySelector('#phone').style.colorScheme==='dark');
      await page.locator('[data-theme=bloom]').click(); assert(await page.locator('#mode').isDisabled());
      assert.equal(await page.locator('#phone').evaluate(node=>node.style.colorScheme),'light');
      await page.emulateMedia({colorScheme:'light'});
    });
    await check(engine + ': all thirteen approved icons update both preview locations',async()=>{
      const buttons=page.locator('[data-icon]');
      for(let i=0;i<await buttons.count();i++){
        const button=buttons.nth(i); const name=await button.getAttribute('aria-label');
        await button.click(); await settled(page);
        assert.equal(await page.locator('#icon-name').innerText(),name);
        assert.equal(await page.locator('#selected-icon-label').innerText(),name);
        assert.equal(await page.locator('#preview-icon').getAttribute('src'),await page.locator('#phone-icon').getAttribute('src'));
        assert.equal(await page.locator('[data-icon][aria-pressed=true]').count(),1);
      }
      assert(await buttons.locator('img').evaluateAll(images=>images.every(image=>image.complete&&image.naturalWidth>0)));
    });
    await check(engine + ': screens, simulated action, and complete reset',async()=>{
      for(const screen of ['library','settings','map']){
        await page.locator(`button[data-screen=${screen}]`).click(); await settled(page);
        assert(await page.locator('#screen-'+screen).isVisible());
        assert.equal(await page.locator('.phone-screen:visible').count(),1);
        if(engine==='chromium') await accessibility(page,'screen-'+screen,'#phone');
        await capture(page,engine+'-'+screen,'#phone');
      }
      await page.locator('#demo-teleport').click();
      assert.match(await page.locator('#demo-status').innerText(),/no real location changed/);
      await page.locator('#demo-teleport').click(); assert.equal(await page.locator('#phone').getAttribute('data-demo-active'),'false');
      await page.locator('#demo-teleport').click(); await page.locator('button[data-screen=settings]').click();
      await page.locator('#reset-preview').click(); await settled(page);
      assert.equal(await page.locator('#phone').getAttribute('data-screen'),'map');
      assert.equal(await page.locator('#phone').getAttribute('data-demo-active'),'false');
      assert.equal(await page.locator('#surface').inputValue(),'solid');
      assert.equal(await page.locator('#mode').inputValue(),'system');
      assert.equal(await page.locator('#icon-name').innerText(),'Prism Jumpgate');
      assert.equal(await page.locator('#theme-name').innerText(),'Bloom');
      await capture(page,engine+'-studio','#studio');
    });
    await check(engine + ': rapid changes remain responsive and keyboard focus is visible',async()=>{
      for(const theme of ['ion','ember','bloom','afterhours','bloom']) await page.locator(`[data-theme=${theme}]`).click();
      await settled(page); assert.equal(await page.locator('#theme-name').innerText(),'Bloom');
      await page.locator('[data-theme=ion]').focus(); await page.keyboard.press('Enter');
      assert.equal(await page.locator('[data-theme=ion]').getAttribute('aria-pressed'),'true');
      assert.notEqual(await page.locator('[data-theme=ion]').evaluate(node=>getComputedStyle(node).outlineStyle),'none');
      await capture(page,engine+'-keyboard-focus','#themes');
      await page.locator('#reset-preview').click();
    });
    await check(engine + ': reduced motion cancels movement',async()=>{
      await page.emulateMedia({reducedMotion:'reduce'});
      await page.locator('#demo-teleport').click();
      assert.equal(await page.locator('.demo-dot').evaluate(node=>getComputedStyle(node).transitionDuration),'0s');
      assert.equal(await page.evaluate(()=>getComputedStyle(document.documentElement).scrollBehavior),'auto');
      await page.locator('[data-theme=ion]').click();
      assert.equal(await page.evaluate(()=>document.getAnimations().length),0);
      await page.locator('#reset-preview').click(); await page.emulateMedia({reducedMotion:'no-preference'});
    });
    await check(engine + ': menu, Escape, same-page links and FAQ work at 320px',async()=>{
      await page.setViewportSize({width:320,height:800}); await page.evaluate(()=>scrollTo({top:0,behavior:'instant'}));
      const menu=page.getByRole('button',{name:'Menu',exact:true});
      await menu.focus(); await page.keyboard.press('Enter'); assert.equal(await menu.getAttribute('aria-expanded'),'true');
      await page.keyboard.press('Tab'); assert.equal(await page.evaluate(()=>document.activeElement.textContent),'Explore');
      await page.keyboard.press('Escape'); assert.equal(await menu.getAttribute('aria-expanded'),'false');
      assert(await menu.evaluate(node=>node===document.activeElement));
      await menu.click(); await capture(page,engine+'-mobile-menu','.site-header');
      await page.locator('#navigation a[href="#studio"]').click(); assert.equal(await menu.getAttribute('aria-expanded'),'false');
      assert.equal(new URL(page.url()).hash,'#studio');
      for(const item of await page.locator('.faq details').all()) { await item.locator('summary').click(); assert(await item.getAttribute('open') !== null); await item.locator('summary').click(); }
      await layout(page);
    });
    await check(engine + ': mobile preview closes, restores position and supports large text',async()=>{
      await page.evaluate(()=>scrollTo({top:0,behavior:'instant'}));
      await page.locator('.hero [data-open-preview]').click(); await settled(page); await layout(page);
      await page.locator('[data-place=riverside]').click();
      assert.equal(await page.locator('#tray-title').innerText(),'Riverside');
      await page.locator('[data-theme=afterhours]').click();
      await page.addStyleTag({content:'html {font-size:200% !important;scroll-behavior:auto !important}'});
      await layout(page); await page.locator('button[data-screen=library]').click(); await layout(page);
      assert(await page.locator('#preview-dialog').evaluate(node=>node.getBoundingClientRect().width>=innerWidth-20));
      await page.locator('#preview-dialog').evaluate(node=>{node.scrollTop=0;});
      await page.screenshot({path:path.join(output,engine+'-dialog-large.png')});
      await page.locator('#close-preview').click();
      await page.waitForFunction(()=>!document.body.classList.contains('preview-open'));
      assert.equal(await page.locator('#studio-slot #studio-body').count(),1);
    });
    await context.close();
    for(const width of [1440,320]) for(const route of ['index.html','guide.html','privacy.html','404.html']) {
      await check(`${engine}: ${route} ${width}px layout and accessibility`,async()=>{
        const {context,page}=await newPage(activeBrowser,{viewport:{width,height:1000}});
        try {
          await go(page,route); await layout(page);
          if(route==='index.html') { await page.locator('#icons').scrollIntoViewIfNeeded(); await page.waitForFunction(()=>[...document.querySelectorAll('#icons img')].every(image=>image.complete&&image.naturalWidth)); }
          if(engine==='chromium') await accessibility(page,route+'-'+width);
          await page.evaluate(()=>scrollTo({top:0,behavior:'instant'}));
          await capture(page,`${engine}-${route}-${width}`);
          if(route==='index.html' && width===1440) await page.screenshot({path:path.join(output,'hero-desktop.png')});
          if(width===320) {
            await page.addStyleTag({content:'html {font-size:200% !important;scroll-behavior:auto !important}'});
            await layout(page); await capture(page,`${engine}-${route}-200pct`);
            if(route==='index.html'){
              await page.locator('[data-theme=ion]').click(); await page.locator('button[data-screen=library]').click(); await layout(page);
              await page.locator('button[data-screen=settings]').click(); await layout(page);
              await page.locator('#reset-preview').click(); await layout(page);
              await capture(page,engine+'-phone-200pct','#phone');
            }
          }
        } finally { await context.close(); }
      });
    }
    await check(engine + ': usable without JavaScript',async()=>{
      const {context,page}=await newPage(activeBrowser,{viewport:{width:320,height:800},javaScriptEnabled:false});
      try { await go(page); assert(await page.locator('#navigation').isVisible()); assert(await page.locator('noscript').isVisible()); await layout(page); await page.locator('#navigation a[href="guide.html"]').click(); assert.match(await page.title(),/Get started/); }
      finally { await context.close(); }
    });
    await check(engine + ': failed preview catalog leaves navigation and recovery usable',async()=>{
      const {context,page}=await newPage(activeBrowser,{viewport:{width:320,height:800}});
      try {
        await page.route('**/catalog.js',route=>route.fulfill({status:200,body:'/* intentionally missing catalog */',contentType:'text/javascript'}));
        await go(page); assert.match(await page.locator('#mode-help').innerText(),/could not load/);
        assert(await page.locator('#demo-teleport').isDisabled()); await page.getByRole('button',{name:'Menu',exact:true}).click(); assert(await page.locator('#navigation').isVisible());
      } finally { await context.close(); }
    });
    if(engine==='chromium') {
      await check('Chromium: forced colors preserves selected controls',async()=>{
        const {context,page}=await newPage(activeBrowser,{viewport:{width:320,height:800},forcedColors:'active'});
        try { await go(page); await page.locator('[data-theme=ion]').click(); assert.equal(await page.locator('[data-theme=ion]').evaluate(node=>getComputedStyle(node).outlineStyle),'solid'); await layout(page); await capture(page,'forced-colors','#themes'); }
        finally { await context.close(); }
      });
      await check('Chromium: loading and privacy observations',async()=>{
        const {context,page}=await newPage(activeBrowser,{viewport:{width:1440,height:1000}});
        try {
          await page.addInitScript(()=>{window.siteCLS=0;new PerformanceObserver(list=>list.getEntries().forEach(entry=>{if(!entry.hadRecentInput)window.siteCLS+=entry.value;})).observe({type:'layout-shift',buffered:true});});
          await go(page);
          report.metrics=await page.evaluate(()=>({domContentLoadedMs:performance.getEntriesByType('navigation')[0].domContentLoadedEventEnd,layoutShift:window.siteCLS,loadedResourceBytes:performance.getEntriesByType('resource').reduce((sum,entry)=>sum+entry.decodedBodySize,0),localStorage:localStorage.length,sessionStorage:sessionStorage.length}));
          assert.equal(report.metrics.localStorage,0); assert.equal(report.metrics.sessionStorage,0); assert.equal((await context.cookies()).length,0);
          assert(report.metrics.layoutShift<.1,JSON.stringify(report.metrics));
        } finally { await context.close(); }
      });
    }
    await activeBrowser.close(); activeBrowser=undefined;
  }
  await check('No external preview requests or browser errors',async()=>{
    assert.equal(report.errors.length,0,JSON.stringify(report.errors));
    const origin=new URL(base).origin;
    assert(report.requests.every(url=>new URL(url).origin===origin),JSON.stringify(report.requests.filter(url=>new URL(url).origin!==origin)));
  });
})().catch(error=>{report.errors.push({fatal:error.stack});console.error(error);}).finally(async()=>{
  await activeBrowser?.close();
  report.requests=[...new Set(report.requests)];
  fs.writeFileSync(path.join(output,'browser-report.json'),JSON.stringify(report,null,2));
  const failed=report.checks.filter(item=>!item.pass);
  console.log(JSON.stringify({passed:report.checks.length-failed.length,failed:failed.length,browserErrors:report.errors.length,accessibilityScans:report.accessibility.length,metrics:report.metrics,output}));
  if(failed.length || report.errors.length) process.exitCode=1;
});
