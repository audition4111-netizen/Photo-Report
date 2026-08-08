/* docx.js(https://www.npmjs.com/package/docx)는 ES 모듈로만 배포돼서, 다른 라이브러리처럼
   <script src="..."> 로 바로 못 붙인다. 이 파일이 모듈로 한 번 읽어서 전역
   window.docx 에 걸어 주면, 나머지 코드(index.html)는 지금까지처럼 그냥
   전역 변수로 쓸 수 있다. 워드 생성은 버튼을 눌렀을 때만 실행되므로,
   이 모듈이 조금 늦게(문서 파싱 뒤에) 로드돼도 문제없다. */
import * as docx from './docx.esm.js';
window.docx = docx;
