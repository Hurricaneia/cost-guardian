from abc import ABC, abstractmethod

class BaseRule(ABC):

	def __init__(self,region):
		self.region = region	

	@abstractmethod
	def run(self):
		pass
