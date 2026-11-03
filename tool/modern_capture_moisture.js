async (page) => {
 const results=[];
 for(const [device,width,height] of [['desktop',1440,1000],['mobile',390,844]]) {
  await page.setViewportSize({width,height}); await page.goto('http://127.0.0.1:8794/');
  const a=page.getByRole('button',{name:'Enable accessibility'});await a.waitFor();await a.evaluate(el=>el.click());
  await page.getByRole('button',{name:'Inspection Findings tools Inspection Findings',exact:true}).click();
  await page.getByRole('button',{name:'Moisture Hold and drag to customize quick tools M%',exact:true}).click();
  if(width<600)await page.getByRole('button',{name:'Hide main toolbar',exact:true}).click();
  for(let n=0;n<2;n++) {
   if(n>0) {
    if(width<600)await page.getByRole('button',{name:'Show main toolbar',exact:true}).click();
    await page.waitForTimeout(500);
    if(await page.getByRole('button',{name:'Inspection Findings tools Inspection Findings',exact:true}).getAttribute('aria-expanded')!=='true') await page.getByRole('button',{name:'Inspection Findings tools Inspection Findings',exact:true}).click();
    await page.waitForTimeout(400);
    await page.getByRole('button',{name:'Moisture Hold and drag to customize quick tools M%',exact:true}).click();
    if(width<600)await page.getByRole('button',{name:'Hide main toolbar',exact:true}).click();
   }
   await page.mouse.click(width<600?260:850,350+n*90);
   const input=page.getByRole('textbox',{name:'Moisture reading',exact:true});await input.waitFor();await page.waitForTimeout(350);
   const state=await input.evaluate(el=>({value:el.value,start:el.selectionStart,end:el.selectionEnd,type:el.type,inputmode:el.inputMode,focused:document.activeElement===el}));
   if(state.value!=='15'||state.start!==0||state.end!==2||!state.focused)throw Error(JSON.stringify(state));
   await page.screenshot({path:`output/playwright/modern-${device}-moisture-${n}.png`,scale:'css'});
   if(n===0){await page.keyboard.type('23');if(await input.inputValue()!=='23')throw Error('Immediate typing failed');await page.getByRole('button',{name:'Save',exact:true}).click();}
   else await page.getByRole('button',{name:'Cancel',exact:true}).click();
   results.push({device,placement:n,...state});
  }
 }
 return results;
}
