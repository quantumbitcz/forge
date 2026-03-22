import React from 'react';

interface Props {
  title: string;
}

const Clean: React.FC<Props> = ({ title }) => {
  return <div className="bg-background text-foreground">{title}</div>;
};
