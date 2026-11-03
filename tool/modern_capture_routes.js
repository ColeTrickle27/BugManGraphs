async (page) => {
  const result=[];
  for (const [device,width,height] of [['desktop',1440,1000],['mobile',390,844]]) {
    await page.setViewportSize({width,height});
    for (const route of ['home','homeSaved','newJob','editJob','trace','presentation']) {
      await page.goto(`http://127.0.0.1:8794/?reviewRoute=${route}${route==='presentation'?'&exportReview=1&fixture=standard':''}`);
      const enable=page.getByRole('button',{name:'Enable accessibility'});
      await enable.waitFor(); await enable.evaluate(el=>el.click());
      await page.getByRole('heading').first().waitFor(); await page.waitForTimeout(500);
      await page.screenshot({path:`output/playwright/modern-${device}-${route}.png`,scale:'css'});
      if(route==='newJob') {
        const contact=page.getByRole('button',{name:'+ Primary/Alternate Contact',exact:true});
        await contact.scrollIntoViewIfNeeded(); await contact.click();
        await page.getByRole('textbox',{name:'Name',exact:true}).waitFor(); await page.waitForTimeout(500);
        await page.screenshot({path:`output/playwright/modern-${device}-contact.png`,scale:'css'});
        await page.getByRole('button',{name:'Cancel',exact:true}).click();
      }
      result.push({device,route});
    }
  }
  return result;
}
