async (page) => {
  const root='http://127.0.0.1:8794/?exportReview=1&fixture=standard';
  async function open(width,height){
    await page.setViewportSize({width,height});await page.goto(root);
    await page.getByRole('button',{name:'Enable accessibility'}).waitFor();
    await page.getByRole('button',{name:'Enable accessibility'}).evaluate(el=>el.click());
    await page.getByRole('button',{name:'File actions',exact:true}).waitFor();
    if(width<600)await page.getByRole('button',{name:'Hide main toolbar',exact:true}).click();
    await page.getByLabel('Fit drawing',{exact:true}).click();
    await page.mouse.move(width-20,42);await page.waitForTimeout(1500);
  }
  async function classify(prefix,start,end){
    await page.getByRole('button',{name:'Sketch / Area',exact:true}).click();
    await page.getByText('Square',{exact:true}).click();
    await page.mouse.move(...start);await page.mouse.down();await page.mouse.move(...end,{steps:10});await page.mouse.up();
    await page.getByText('Classify shape',{exact:true}).waitFor();
    await page.screenshot({path:`output/playwright/${prefix}-classification.png`,scale:'css'});
    await page.getByRole('button',{name:'Classify later',exact:true}).click();
  }
  await open(1400,900);
  await page.screenshot({path:'output/playwright/desktop-final.png',scale:'css'});
  await page.mouse.click(1250,350,{button:'right'});
  await page.getByRole('menuitem',{name:'Callout box',exact:true}).waitFor();
  await page.screenshot({path:'output/playwright/desktop-context.png',scale:'css'});
  await page.keyboard.press('Escape');
  await page.mouse.click(460,245);
  await page.screenshot({path:'output/playwright/desktop-callout-selection.png',scale:'css'});
  await classify('desktop',[900,200],[1050,350]);
  await open(390,844);
  await page.screenshot({path:'output/playwright/mobile-final.png',scale:'css'});
  await page.mouse.click(330,250,{button:'right'});
  await page.getByRole('menuitem',{name:'Callout box',exact:true}).waitFor();
  await page.screenshot({path:'output/playwright/mobile-context.png',scale:'css'});
  await page.keyboard.press('Escape');
  await classify('mobile',[140,300],[250,410]);
  return 'Desktop/mobile workflow captures complete';
}
