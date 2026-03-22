import React from 'react';

const token = "sk-secret-key-12345";

const Bad = (props: any) => {
  console.log("rendering component", props);

  try {
    // some risky operation
  } catch(e) {}

  return <div className="bg-white text-black">{props.title}</div>;
};

export default Bad;
